#pragma once

#include "HydroGPU/Solver.h"
#include "CLApp/CLApp.h"
#include "Tensor/Vector.h"

//passing from cmd-line to app
struct HydroGPUArgs {
	std::string solverName;
	HydroGPUArgs();
};

struct HydroGPUApp : public ::CLApp::CLApp {
	typedef ::CLApp::CLApp Super;

	HydroGPUArgs hydroArgs;

	GLuint fluidTex;
	GLuint gradientTex;
	
	cl::ImageGL fluidTexMem;		//data is written to this buffer before rendering
	cl::ImageGL gradientTexMem;	//as it is written, data is read from this for mapping values to colors

	std::shared_ptr<Solver> solver;

	cl_int2 size;
	int doUpdate;	//0 = no, 1 = continuous, 2 = single step
	int maxFrames;	//run this far and pause.  -1 = forever = default
	int currentFrame;

	bool leftButtonDown;
	bool rightButtonDown;
	bool leftShiftDown;
	bool rightShiftDown;
	bool leftGuiDown;
	bool rightGuiDown;
	Tensor::Vector<real,2> mousePos, mouseVel;
	Tensor::Vector<int,2> screenSize;
	float viewZoom;
	Tensor::Vector<float,2> viewPos;
	float aspectRatio;
	
	real2 xmin, xmax;
	bool useFixedDT;
	real fixedDT;
	real cfl;
	int displayMethod;
	float displayScale;
	
	HydroGPUApp();

	virtual int main(std::vector<std::string> args);
	virtual void init();
	virtual void shutdown();
	virtual void resize(int width, int height);
	virtual void update();
	virtual void sdlEvent(SDL_Event &event);
};
