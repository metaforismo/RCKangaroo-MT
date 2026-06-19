#include "macos/MetalSmoke.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static std::string NSErrorToString(NSError* err)
{
	if (!err)
		return "unknown Metal error";
	const char* msg = [[err localizedDescription] UTF8String];
	return msg ? std::string(msg) : "unknown Metal error";
}

bool RCKMetalSmoke(std::string& error)
{
	@autoreleasepool
	{
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (!device)
		{
			error = "no Metal device available";
			return false;
		}

		NSString* source =
			@"#include <metal_stdlib>\n"
			@"using namespace metal;\n"
			@"kernel void add_one(device uint* values [[buffer(0)]], uint id [[thread_position_in_grid]]) {\n"
			@"  if (id < 4) values[id] += 1;\n"
			@"}\n";

		NSError* ns_error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&ns_error];
		if (!library)
		{
			error = NSErrorToString(ns_error);
			return false;
		}

		id<MTLFunction> function = [library newFunctionWithName:@"add_one"];
		if (!function)
		{
			error = "failed to load add_one function";
			return false;
		}

		id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&ns_error];
		if (!pipeline)
		{
			error = NSErrorToString(ns_error);
			return false;
		}

		unsigned int values[4] = {1, 2, 3, 4};
		id<MTLBuffer> buffer = [device newBufferWithBytes:values length:sizeof(values) options:MTLResourceStorageModeShared];
		if (!buffer)
		{
			error = "failed to allocate Metal buffer";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}

		id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
		id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
		[encoder setComputePipelineState:pipeline];
		[encoder setBuffer:buffer offset:0 atIndex:0];
		[encoder dispatchThreads:MTLSizeMake(4, 1, 1) threadsPerThreadgroup:MTLSizeMake(4, 1, 1)];
		[encoder endEncoding];
		[command_buffer commit];
		[command_buffer waitUntilCompleted];

		if ([command_buffer status] != MTLCommandBufferStatusCompleted)
		{
			error = "Metal command buffer did not complete";
			return false;
		}

		unsigned int* out = (unsigned int*)[buffer contents];
		if (out[0] != 2 || out[1] != 3 || out[2] != 4 || out[3] != 5)
		{
			error = "Metal smoke output mismatch";
			return false;
		}

		return true;
	}
}
