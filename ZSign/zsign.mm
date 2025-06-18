#include "zsign.hpp"
#include "common/common.h"
#include "common/json.h"
#include "openssl.h"
#include "macho.h"
#include "bundle.h"
#include <libgen.h>
#include <dirent.h>
#include <getopt.h>
#include <stdlib.h>
#include <OpenSSL/ocsp.h>
#include <OpenSSL/x509.h>
#include <OpenSSL/pem.h>
#include <OpenSSL/bio.h>
#include <OpenSSL/ssl.h>
#include <OpenSSL/err.h>
#include <OpenSSL/asn1.h>

NSString* getTmpDir() {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	return [[[paths objectAtIndex:0] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"tmp"];
}

extern "C" {

bool InjectDyLib(NSString *filePath, NSString *dylibPath, bool weakInject, bool bCreate) {
	ZTimer gtimer;
	@autoreleasepool {
		// Convert NSString to std::string
		std::string filePathStr = [filePath UTF8String];
		std::string dylibPathStr = [dylibPath UTF8String];

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		bool success = machO.InjectDyLib(weakInject, dylibPathStr.c_str(), bCreate);

		machO.Free();

		if (success) {
			gtimer.Print(">>> Dylib injected successfully!");
			return true;
		} else {
			gtimer.Print(">>> Failed to inject dylib.");
			return false;
		}
	}
}

bool ListDylibs(NSString *filePath, NSMutableArray *dylibPathsArray) {
	ZTimer gtimer;
	@autoreleasepool {
		// Convert NSString to std::string
		std::string filePathStr = [filePath UTF8String];

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		std::vector<std::string> dylibPaths = machO.ListDylibs();

		if (!dylibPaths.empty()) {
			gtimer.Print(">>> List of dylibs in the Mach-O file:");
            for (vector<std::string>::iterator it = dylibPaths.begin(); it < dylibPaths.end(); ++it) {
                std::string dylibPath = *it;
				NSString *dylibPathStr = [NSString stringWithUTF8String:dylibPath.c_str()];
				[dylibPathsArray addObject:dylibPathStr];
			}
		} else {
			gtimer.Print(">>> No dylibs found in the Mach-O file.");
		}

		machO.Free();

		return true;
	}
}

bool UninstallDylibs(NSString *filePath, NSArray<NSString *> *dylibPathsArray) {
	ZTimer gtimer;
	@autoreleasepool {
		std::string filePathStr = [filePath UTF8String];
		std::set<std::string> dylibsToRemove;

		for (NSString *dylibPath in dylibPathsArray) {
			dylibsToRemove.insert([dylibPath UTF8String]);
		}

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		machO.RemoveDylib(dylibsToRemove);

		machO.Free();

		gtimer.Print(">>> Dylibs uninstalled successfully!");
		return true;
	}
}



bool ChangeDylibPath(NSString *filePath, NSString *oldPath, NSString *newPath) {
	ZTimer gtimer;
	@autoreleasepool {
		// Convert NSString to std::string
		std::string filePathStr = [filePath UTF8String];
		std::string oldPathStr = [oldPath UTF8String];
		std::string newPathStr = [newPath UTF8String];

		ZMachO machO;
		bool initSuccess = machO.Init(filePathStr.c_str());
		if (!initSuccess) {
			gtimer.Print(">>> Failed to initialize ZMachO.");
			return false;
		}

		bool success = machO.ChangeDylibPath(oldPathStr.c_str(), newPathStr.c_str());

		machO.Free();

		if (success) {
			gtimer.Print(">>> Dylib path changed successfully!");
			return true;
		} else {
			gtimer.Print(">>> Failed to change dylib path.");
			return false;
		}
	}
}

NSError* makeErrorFromLog(const std::vector<std::string>& vec) {
    NSMutableString *result = [NSMutableString string];
    
    for (size_t i = 0; i < vec.size(); ++i) {
        // Convert each std::string to NSString
        NSString *str = [NSString stringWithUTF8String:vec[i].c_str()];
        [result appendString:str];
        
        // Append newline if it's not the last element
        if (i != vec.size() - 1) {
            [result appendString:@"\n"];
        }
    }
    
    NSDictionary* userInfo = @{
        NSLocalizedDescriptionKey : result
    };
    return [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:userInfo];
}

ZSignAsset zSignAsset;

void zsign(NSString *appPath,
          NSData *prov,
          NSData *key,
          NSString *pass,
          NSProgress* progress,
          void(^completionHandler)(BOOL success, NSError *error)
          )
{
    ZTimer gtimer;
    ZTimer timer;
    timer.Reset();
    
	bool bForce = false;
	bool bWeakInject = false;
	bool bDontGenerateEmbeddedMobileProvision = YES;
	
	string strPassword;

	string strDyLibFile;
	string strOutputFile;

	string strEntitlementsFile;

    const char* strPKeyFileData = (const char*)[key bytes];
    const char* strProvFileData = (const char*)[prov bytes];
	strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
	
	
	string strPath = [appPath cStringUsingEncoding:NSUTF8StringEncoding];
    
    ZLog::logs.clear();

	__block ZSignAsset zSignAsset;
	
    if (!zSignAsset.InitSimple(strPKeyFileData, (int)[key length], strProvFileData, (int)[prov length], strPassword)) {
        completionHandler(NO, makeErrorFromLog(ZLog::logs));
        ZLog::logs.clear();
		return;
	}
    
	bool bEnableCache = true;
	string strFolder = strPath;
	
	__block ZAppBundle bundle;
	bool success = bundle.ConfigureFolderSign(&zSignAsset, strFolder, "", "", "", strDyLibFile, bForce, bWeakInject, bEnableCache, bDontGenerateEmbeddedMobileProvision);

    if(!success) {
        completionHandler(NO, makeErrorFromLog(ZLog::logs));
        ZLog::logs.clear();
        return;
    }
    
    int filesNeedToSign = bundle.GetSignCount();
    [progress setTotalUnitCount:filesNeedToSign];
    bundle.progressHandler = [&progress] {
        [progress setCompletedUnitCount:progress.completedUnitCount + 1];
    };
    
    


    ZLog::PrintV(">>> Files Need to Sign: \t%d\n", filesNeedToSign);
    bool bRet = bundle.StartSign(bEnableCache);
    timer.PrintResult(bRet, ">>> Signed %s!", bRet ? "OK" : "Failed");
    gtimer.Print(">>> Done.");
    NSError* signError = nil;
    if(!bundle.signFailedFiles.empty()) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey : [NSString stringWithUTF8String:bundle.signFailedFiles.c_str()]
        };
        signError = [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:userInfo];
    }
    
    completionHandler(YES, signError);
    ZLog::logs.clear();
    
	return;
}

NSString* getTeamId(NSData *prov,
                    NSData *key,
                    NSString *pass) {
    string strPassword;

    const char* strPKeyFileData = (const char*)[key bytes];
    const char* strProvFileData = (const char*)[prov bytes];
    strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];

    ZLog::logs.clear();


    __block ZSignAsset zSignAsset;

    if (!zSignAsset.InitSimple(strPKeyFileData, (int)[key length], strProvFileData, (int)[prov length], strPassword)) {
        ZLog::logs.clear();
        return nil;
    }
    NSString* teamId = [NSString stringWithUTF8String:zSignAsset.m_strTeamId.c_str()];
    return teamId;
}

int checkCert(NSData *prov,
              NSData *key,
              NSString *pass,
              BOOL ocsp,
              void(^completionHandler)(int status, NSDate* expirationDate, NSString *error)) {
    const char* strPKeyFileData = (const char*)[key bytes];
    const char* strProvFileData = (const char*)[prov bytes];
    string strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
    
    ZLog::logs.clear();


    __block ZSignAsset zSignAsset;
    
    if (!zSignAsset.InitSimple(strPKeyFileData, (int)[key length], strProvFileData, (int)[prov length], strPassword)) {
        ZLog::logs.clear();
        completionHandler(2, nil, @"Unable to initialize certificate. Please check your password.");
        return -1;
    }
    
    X509* cert = (X509*)zSignAsset.m_x509Cert;
    BIO *brother1;
    unsigned long issuerHash = X509_issuer_name_hash((X509*)cert);
    if (0x817d2f7a == issuerHash) {
        brother1 = BIO_new_mem_buf(appleDevCACert, (int)strlen(appleDevCACert));
    } else if (0x9b16b75c == issuerHash) {
        brother1 = BIO_new_mem_buf(appleDevCACertG3, (int)strlen(appleDevCACertG3));
    } else {
        completionHandler(2, nil, @"Unable to determine issuer of the certificate. It is signed by Apple Developer?");
        return -2;
    }
    
    if (!brother1)
    {
        completionHandler(2, nil, @"Unable to initialize issuer certificate.");
        return -3;
    }
    
    X509 *issuer = PEM_read_bio_X509(brother1, NULL, 0, NULL);
    
    if (!cert || !issuer) {
        completionHandler(2, nil, @"Error loading cert or issuer");
        return -4;
    }


    if (!ocsp) {
        ZLog::Warn("Not testing the OCSP url, expiration date will not be shown.");
        completionHandler(0, [NSDate now], nil);
        return 1;
    }

    
    // Extract OCSP URL from cert
    STACK_OF(ACCESS_DESCRIPTION)* aia = (STACK_OF(ACCESS_DESCRIPTION)*)X509_get_ext_d2i((X509*)cert, NID_info_access, 0, 0);
    if (!aia) {
        completionHandler(2, nil, @"No AIA (OCSP) extension found in certificate");
        return -5;
    }
    
    ASN1_IA5STRING* uri = nullptr;
    for (int i = 0; i < sk_ACCESS_DESCRIPTION_num(aia); i++) {
        ACCESS_DESCRIPTION* ad = sk_ACCESS_DESCRIPTION_value(aia, i);
        if (OBJ_obj2nid(ad->method) == NID_ad_OCSP &&
            ad->location->type == GEN_URI) {
            uri = ad->location->d.uniformResourceIdentifier;
            
            break;
        }
    }

    
    if (!uri) {
        completionHandler(2, nil, @"No OCSP URI found in certificate.");
        return -6;
    }

    OCSP_REQUEST* req = OCSP_REQUEST_new();
    OCSP_CERTID* cert_id = OCSP_cert_to_id(nullptr, (X509*)cert, issuer);
    OCSP_request_add0_id(req, cert_id);  // Ownership transferred to request
    cert_id = OCSP_cert_to_id(nullptr, (X509*)cert, issuer);
    unsigned char* der = 0;
    int len = i2d_OCSP_REQUEST(req, &der);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:(const char *)uri->data]]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[NSData dataWithBytes:der length:len]];
    [request setValue:@"application/ocsp-request" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/ocsp-response" forHTTPHeaderField:@"Accept"];
    
    OPENSSL_free(der);
    if (aia) {
        sk_ACCESS_DESCRIPTION_pop_free(aia, ACCESS_DESCRIPTION_free);
    }
    OCSP_REQUEST_free(req);
    X509_free(issuer);
    BIO_free(brother1);

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data,
                                                                NSURLResponse * _Nullable response,
                                                                NSError * _Nullable error) {
        if (error) {
            completionHandler(0, [NSDate now], nil);
            //completionHandler(2, nil, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 200 && data) {
            // You can save `data` or parse the response
            const void *respBytes = [data bytes];
            OCSP_RESPONSE *resp;
            d2i_OCSP_RESPONSE(&resp, (const unsigned char**)&respBytes, data.length);
            OCSP_BASICRESP *basic = OCSP_response_get1_basic(resp);
            ASN1_TIME *expirationDateAsn1 = X509_get_notAfter(cert);
            NSString *fullDateString = [NSString stringWithFormat:@"20%s", expirationDateAsn1->data];

            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyyMMddHHmmss'Z'";
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.locale = NSLocale.currentLocale;
            NSDate *expirationDate = [formatter dateFromString:fullDateString];

            int status, reason;
            if (OCSP_resp_find_status(basic, cert_id, &status, &reason, NULL, NULL, NULL)) {
                completionHandler(status, expirationDate, nil);
            } else {
                completionHandler(2, expirationDate, nil);
            }
            
            OCSP_CERTID_free(cert_id);
            OCSP_BASICRESP_free(basic);
            OCSP_RESPONSE_free(resp);
            
            
        } else {
            completionHandler(2, nil, @"Invalid response or no data");
            return;
        }
    }];

    [task resume];
    return 1;
}

}
