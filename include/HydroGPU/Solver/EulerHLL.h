#pragma once

#include "HydroGPU/Solver/HLL.h"

namespace HydroGPU {
struct HydroGPUApp;
namespace Solver {

struct EulerHLL : public HLL {
	typedef HLL Super;

	EulerHLL(HydroGPUApp&);

protected:
	virtual std::string getFluxSource();
};

}
}

