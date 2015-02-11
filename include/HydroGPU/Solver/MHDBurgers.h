#pragma once

#include "HydroGPU/Solver/Solver.h"

namespace HydroGPU {
struct HydroGPUApp;
namespace Solver {

struct MHDBurgers : public Solver {
	typedef Solver Super;
	MHDBurgers(HydroGPUApp& app);
protected:

	cl::Buffer interfaceVelocityBuffer;
	cl::Buffer interfaceMagneticFieldBuffer;
	cl::Buffer fluxBuffer;
	cl::Buffer pressureBuffer;
	//for removing magnetic field divergence
	cl::Buffer magneticFieldDivergenceBuffer;
	cl::Buffer magneticFieldPotentialBuffer;

	cl::Kernel calcCFLKernel;
	cl::Kernel calcInterfaceVelocityKernel;
	cl::Kernel calcVelocityFluxKernel;
	cl::Kernel calcInterfaceMagneticFieldKernel;
	cl::Kernel calcMagneticFieldFluxKernel;
	cl::Kernel calcFluxDerivKernel;
	cl::Kernel computePressureKernel;
	cl::Kernel diffuseMomentumKernel;
	cl::Kernel diffuseWorkKernel;
	cl::Kernel calcMagneticFieldDivergenceKernel;
	cl::Kernel magneticPotentialPoissonRelaxKernel;
	cl::Kernel magneticFieldRemoveDivergenceKernel;

	//matches MHDRoe -- belongs in the MHDEquation class maybe?
	cl::Kernel initVariablesKernel;

public:
	virtual void init();

protected:	
	virtual std::vector<std::string> getProgramSources();
	
	virtual void calcTimestep();
	virtual void step();

	void magneticFieldPotentialBoundary();
};

}
}

