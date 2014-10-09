#include "HydroGPU/Solver/MHDRoe.h"
#include "HydroGPU/Equation/MHD.h"
#include "HydroGPU/HydroGPUApp.h"
#include "Common/File.h"

namespace HydroGPU {
namespace Solver {

MHDRoe::MHDRoe(HydroGPUApp& app_)
: Super(app_)
{
	equation = std::make_shared<HydroGPU::Equation::MHD>(*this);
}

void MHDRoe::init() {
	Super::init();

	//allocate flux flag buffer for determining if any flux values had to be pre-filled for bad eigenstate areas
	fluxFlagBuffer = clAlloc(sizeof(char) * getVolume() * app.dim);

	//just like ordinary calcMHDFluxKernel -- and calls the ordinary
	// -- but with an extra step to bail out of the associated fluxFlag is already set 
	calcMHDFluxKernel = cl::Kernel(program, "calcMHDFlux");
	app.setArgs(calcMHDFluxKernel, fluxBuffer, stateBuffer, eigenvaluesBuffer, eigenvectorsBuffer, eigenvectorsInverseBuffer, deltaQTildeBuffer, dtBuffer, fluxFlagBuffer);

	//setup our eigenbasis kernel to accept these extras
	calcEigenBasisKernel.setArg(5, fluxBuffer);
	calcEigenBasisKernel.setArg(6, fluxFlagBuffer);
}

std::vector<std::string> MHDRoe::getProgramSources() {
	std::vector<std::string> sources = Super::getProgramSources();
	sources.push_back(Common::File::read("MHDRoe.cl"));
	return sources;
}


void MHDRoe::initStep() {
	//MHD-Roe is special in that it can write fluxes during the calc eigen basis kernel
	//(in the case of negative fluxes)
	// so for that, I'm going to fill the flux kernel to some flag beforehand.
	// zero is a safe flag, right?  no ... not for steady states ...
	commands.enqueueFillBuffer(fluxFlagBuffer, 0, 0, getVolume() * app.dim);
	
	//and fill buffer
	Super::initStep();
}

//override parent call
//call this instead
//it'll call through the CL code if it's needed
void MHDRoe::calcFlux() {
	commands.enqueueNDRangeKernel(calcMHDFluxKernel, offsetNd, globalSize, localSize);
}

}
}

