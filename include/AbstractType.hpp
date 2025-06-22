#pragma once

#include <cstdint>
#include <string>
#include <type_traits>

namespace tulip {
	enum class AbstractTypeKind : uint8_t {
		Primitive,
		FloatingPoint,
		Other,
	};

	class AbstractType {
	public:
		size_t m_size;
		AbstractTypeKind m_kind;

		template <class Type>
		static AbstractType from();
	};
}
