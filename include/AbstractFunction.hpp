#pragma once

#include "AbstractType.hpp"

#include <string>
#include <type_traits>
#include <vector>

namespace tulip {
	class AbstractFunction {
		template <class FunctionType>
		struct Generator {
			static AbstractFunction generate() {
				return AbstractFunction();
			}
		};

		template <class Return, class... Parameters>
		struct Generator<Return(Parameters...)> {
			static AbstractFunction generate();
		};

	public:
		AbstractType m_return;
		std::vector<AbstractType> m_parameters;

		template <class FunctionType>
		static AbstractFunction from() {
			return Generator<FunctionType>::generate();
		}

		template <class Return, class... Parameters>
		static AbstractFunction from(Return (*)(Parameters...));
	};
}
