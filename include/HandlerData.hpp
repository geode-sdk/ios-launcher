#pragma once

#include "AbstractFunction.hpp"

#include <memory>

namespace tulip {
	class CallingConvention;

	using HandlerHandle = size_t;

	class HandlerMetadata {
	public:
		std::shared_ptr<CallingConvention> m_convention;

		AbstractFunction m_abstract;
	};
}
