#include "HydroGPU/Solver/Roe.h"
#include "HydroGPU/HydroGPUApp.h"

namespace HydroGPU {
namespace Solver {

Roe::Roe(HydroGPUApp* app_)
: Super(app_)
{}

void Roe::initBuffers() {
	Super::initBuffers();
	eigenvaluesBuffer = cl.alloc(sizeof(real) * getEigenSpaceDim() * getVolume() * app->dim, "Roe::eigenvaluesBuffer");
	eigenvectorsBuffer = cl.alloc(sizeof(real) * getEigenTransformStructSize() * getVolume() * app->dim, "Roe::eigenvectorsBuffer");
	deltaQTildeBuffer = cl.alloc(sizeof(real) * getEigenSpaceDim() * getVolume() * app->dim, "Roe::deltaQTildeBuffer");
}

//if the eigen transform is transforming from/to conservative/characteristics
//then it should be getEigenSpaceDim() * numStates * 2
// but I don't think anyone who uses the default implementation changes the # of characteristics away from the # of conservative
int Roe::getEigenTransformStructSize() {
	return getEigenSpaceDim() * getEigenSpaceDim() * 2;	//times two for forward and inverse
}

/*
Some solvers advect a different number of variables (particularly less variables) 
 than the total number of state variables.
Specifically because some variables are only driven by source terms, or are altogether static.
*/
int Roe::getEigenSpaceDim() {
	return numStates();
}

void Roe::initKernels() {
	Super::initKernels();

	calcEigenBasisKernel = cl::Kernel(program, "calcEigenBasis");
	CLCommon::setArgs(calcEigenBasisKernel, eigenvaluesBuffer, eigenvectorsBuffer, stateBuffer);
	
	calcCellTimestepKernel = cl::Kernel(program, "calcCellTimestep");
	CLCommon::setArgs(calcCellTimestepKernel,
		dtBuffer,
//Hydrodynamics ii
#if 1
		eigenvaluesBuffer);
#endif
//Toro 16.38
#if 0
		stateBuffer);
#endif	

	calcDeltaQTildeKernel = cl::Kernel(program, "calcDeltaQTilde");
	CLCommon::setArgs(calcDeltaQTildeKernel, deltaQTildeBuffer, eigenvectorsBuffer, stateBuffer);
}	

void Roe::init() {
	Super::init();
	calcFluxKernel.setArg(2, eigenvaluesBuffer);
	calcFluxKernel.setArg(3, eigenvectorsBuffer);
	calcFluxKernel.setArg(4, deltaQTildeBuffer); 
}

std::vector<std::string> Roe::getProgramSources() {
	std::vector<std::string> sources = Super::getProgramSources();
	sources.push_back("#define EIGEN_TRANSFORM_STRUCT_SIZE "+std::to_string(getEigenTransformStructSize())+"\n");
	sources.push_back("#define EIGEN_SPACE_DIM "+std::to_string(getEigenSpaceDim())+"\n");
	
	std::vector<std::string> added = getEigenProgramSources();
	sources.insert(sources.end(), added.begin(), added.end());
		
	sources.push_back("#include \"Roe.cl\"\n");
	
	return sources;
}

std::vector<std::string> Roe::getEigenProgramSources() {
	return {
		"#include \"RoeEigenfieldLinear.cl\"\n"
	};
}

void Roe::initFlux() {
	//compute eigenbasis here, once
	//then, because we're not integrating separate dimensions separately, the states won't get intermediately changed and we won't have to update this value
	commands.enqueueNDRangeKernel(calcEigenBasisKernel, offsetNd, globalSize, localSize);
}

real Roe::calcTimestep() {
	initFlux();
	commands.enqueueNDRangeKernel(calcCellTimestepKernel, offsetNd, globalSize, localSize);
	return findMinTimestep();
}

void Roe::step(real dt) {
	//no need to re-init flux here unless we are separating integraion per-side
	integrator->integrate(dt, [&](cl::Buffer derivBuffer) {
		calcDeriv(derivBuffer, dt);
	});
}

void Roe::calcDeriv(cl::Buffer derivBuffer, real dt) {
	commands.enqueueNDRangeKernel(calcDeltaQTildeKernel, offsetNd, globalSize, localSize);
	calcFlux(dt);
	
	calcFluxDerivKernel.setArg(0, derivBuffer);
	commands.enqueueNDRangeKernel(calcFluxDerivKernel, offsetNd, globalSize, localSize);
}

void Roe::calcFlux(real dt) {
	calcFluxKernel.setArg(5, dt);
	commands.enqueueNDRangeKernel(calcFluxKernel, offsetNd, globalSize, localSize);
}

}
}
