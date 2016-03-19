#pragma once

#include "HydroGPU/Boundary/Boundary.h"
#include "Common/Exception.h"

namespace HydroGPU {
namespace Equation {

//TODO organize this
//it's in each equation as well as here
//probably put back in Solver.h along with BOUNDARY_KERNEL_* enum
enum {
	BOUNDARY_METHOD_NONE = -1,
	BOUNDARY_METHOD_PERIODIC,
	BOUNDARY_METHOD_MIRROR,
	BOUNDARY_METHOD_FREEFLOW,
	NUM_BOUNDARY_METHODS
};

struct SelfGravitationInterface {
	virtual int gravityGetBoundaryKernelForBoundaryMethod(int dim, int minmax) = 0;
};

template<typename Parent>
struct SelfGravitationBehavior : public Parent, public SelfGravitationInterface {
	typedef Parent Super;
	using Super::Super;
	virtual int gravityGetBoundaryKernelForBoundaryMethod(int dim, int minmax);
};

template<typename Parent>
int SelfGravitationBehavior<Parent>::gravityGetBoundaryKernelForBoundaryMethod(int dim, int minmax) {
	switch (Super::app->boundaryMethods(dim, minmax)) {
	case BOUNDARY_METHOD_NONE:
		return BOUNDARY_KERNEL_NONE;
	case BOUNDARY_METHOD_PERIODIC:
		return BOUNDARY_KERNEL_PERIODIC;
	case BOUNDARY_METHOD_MIRROR:
		return BOUNDARY_KERNEL_FREEFLOW;
	case BOUNDARY_METHOD_FREEFLOW:
		return BOUNDARY_KERNEL_FREEFLOW;
	}
	throw Common::Exception() << "got an unknown boundary method " << Super::app->boundaryMethods(dim, minmax) << " for dim " << dim;
}

}
}
