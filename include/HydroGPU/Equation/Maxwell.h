#pragma once

#include "HydroGPU/Equation/Equation.h"
#include <vector>
#include <string>

namespace HydroGPU {
namespace Solver {
struct Solver;
}
namespace Equation {

struct Maxwell : public Equation {
	typedef Equation Super;
	Maxwell(HydroGPU::Solver::Solver* solver);
	virtual void getProgramSources(std::vector<std::string>& sources);
	virtual int stateGetBoundaryKernelForBoundaryMethod(int dim, int state, int minmax);
};

}
}

