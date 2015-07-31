#pragma once

#include "HydroGPU/Solver/Solver.h"
#include "HydroGPU/HydroGPUApp.h"
#include <memory>

namespace HydroGPU {
namespace Solver {

template<typename Parent>
struct SelfGravitationBehavior : public Parent {
	typedef Parent Super;
	using Super::Super;
protected:
	std::shared_ptr<HydroGPU::Solver::SelfGravitation> selfgrav;

public:
	virtual void init() {
		selfgrav = std::make_shared<SelfGravitation>(this);
		Super::init();
	}

	virtual void setupConvertToTexKernelArgs() {
		Super::setupConvertToTexKernelArgs();
		selfgrav->setupConvertToTexKernelArgs();
	}

protected:
	virtual void initBuffers() {
		Super::initBuffers();
		selfgrav->initBuffers();
	}

	virtual void initKernels() {
		Super::initKernels();
		selfgrav->initKernels();
	}

	virtual std::vector<std::string> getProgramSources() {
		std::vector<std::string> sources = Super::getProgramSources();
		std::vector<std::string> added = selfgrav->getProgramSources();
		sources.insert(sources.end(), added.begin(), added.end());
		return sources;
	}

	struct Converter : public Super::Converter {
		typedef typename Super::Converter Super;
		std::vector<real> potentialVec;

		//I'm going to put solid flag buffers here for now because I'm lazy
		std::vector<char> solidVec;
		
		Converter(Solver* solver)
		: Super(solver)
		, potentialVec(solver->getVolume())
		, solidVec(solver->getVolume())
		{}

		virtual int numChannels() {
			return Super::numChannels() + 1 + 1;	//1 for potential energy, 1 for solid 
		}
		
		virtual void setValues(int index, const std::vector<real>& cellValues) {
			Super::setValues(index, cellValues);
			potentialVec[index] = cellValues[cellValues.size()-2];
			solidVec[index] = cellValues[cellValues.size()-1];
		}
		
		virtual void toGPU() {
			Super::toGPU();
			SelfGravitationBehavior* owner = dynamic_cast<SelfGravitationBehavior*>(Super::solver);
			owner->selfgrav->resetState(Super::stateVec, potentialVec, solidVec);
		}
		
		virtual void fromGPU() {
			Super::fromGPU();
			SelfGravitationBehavior* owner = dynamic_cast<SelfGravitationBehavior*>(Super::solver);
			owner->commands.enqueueReadBuffer(owner->selfgrav->potentialBuffer, CL_TRUE, 0, sizeof(real) * owner->getVolume(), potentialVec.data());
			owner->commands.enqueueReadBuffer(owner->selfgrav->solidBuffer, CL_TRUE, 0, sizeof(char) * owner->getVolume(), solidVec.data());
			owner->commands.finish();
		}
		
		virtual real getValue(int index, int channel) {
			if (channel == Super::solver->numStates()) return potentialVec[index];
			if (channel == Super::solver->numStates()+1) return solidVec[index];
			return Super::getValue(index, channel);
		}
	};
	friend struct Converter;

	virtual std::shared_ptr<Solver::Converter> createConverter() {
		return std::make_shared<Converter>(this);
	}

	virtual std::vector<std::string> getSaveChannelNames() {
		std::vector<std::string> channelNames = Super::getSaveChannelNames();
		channelNames.push_back("potential");
		return channelNames;
	}
};

}
}
