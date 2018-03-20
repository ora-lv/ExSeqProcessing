// Multiple GPU version of cuFFT_check that uses multiple GPU's
// This program creates a real-valued 3D function sin(x)*cos(y)*cos(z) and then 
// takes the forward and inverse Fourier Transform, with the necessary scaling included. 
// The output of this process should match the input function

// includes, system
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <complex.h>

// includes, project
#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <cufft.h>
#include <cuComplex.h>
//CUFFT Header file
#include <cufftXt.h>

namespace cufftutils {

__global__ 
void initialize(int N, float* data, cufftComplex *f1, cufftComplex *f2)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) {
        // Initialize complex array from real input
        f1[idx].x = data[idx];
        f1[idx].y = 0.0; // complex component

        /*FIXME should this be real?*/
        // Initialize final array
        f2[idx].x = 0.0;
        f2[idx].y = 0.0;
    }

    return;
}

__global__
void scaleResult(int N, cufftComplex *f)
{
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < N) {
        f[idx].x = f[idx].x / ( (float)N );
        f[idx].y = f[idx].y / ( (float)N );
    }

    return;
}

// multiply, scale both arrays, keep product inplace on b
__global__
void ComplexPointwiseMulAndScale(cufftComplex *a, cufftComplex *b, int size, float scale)
{
    const int numThreads = blockDim.x * gridDim.x;
    const int threadID = blockIdx.x * blockDim.x + threadIdx.x;
    cufftComplex c;
    for (int i = threadID; i < size; i += numThreads)
    {
        c = cuCmulf(a[i], b[i]);
        b[i] = make_cuFloatComplex(scale*cuCrealf(c), scale*cuCimagf(c) );
    }
    return;
}

static __device__ __host__ inline cufftComplex ComplexMul(cufftComplex a, cufftComplex b)
{
    cufftComplex c;
    c.x = a.x * b.x - a.y * b.y;
    c.y = a.x * b.y + a.y * b.x;
    return c;
}

static __device__ __host__ inline cufftComplex ComplexAdd(cufftComplex a, cufftComplex b)
{
    cufftComplex c;
    c.x = a.x + b.x;
    c.y = a.y + b.y;
    return c;
}


void convolve_host(const cufftComplex *signal, long signal_size,
                      const cufftComplex *filter_kernel, long filter_kernel_size,
                                    cufftComplex *filtered_signal)
{
        long minRadius = filter_kernel_size / 2;
        long maxRadius = filter_kernel_size - minRadius;

        // Loop over output element indices
        for (int i = 0; i < signal_size; ++i)
        {
            filtered_signal[i].x = filtered_signal[i].y = 0;

            // Loop over convolution indices
            for (int j = - maxRadius + 1; j <= minRadius; ++j)
            {
                int k = i + j;

                if (k >= 0 && k < signal_size)
                {
                    filtered_signal[i] = ComplexAdd(filtered_signal[i], ComplexMul(signal[k], filter_kernel[minRadius - j]));
                }
            }
        }
}

int conv_handler_batch(float* hostI, float* hostF, float* hostO, int algo, int* size, int* filterdimA, int benchmark) {
     
    int rank = 3; // hardcoded, func only supports 3D convolutions
    int nGPUs;
    cudaGetDeviceCount(&nGPUs);

    int N = size[0] * size[1] * size[2];
    printf("Using %d GPUs on a %dx%dx%d grid. N=%d\n",nGPUs, size[0], size[1], size[2], N);
    /*int N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];*/
    int batch = 2;
    int size_of_one_set = N * sizeof(cufftComplex);
    int size_of_data = size_of_one_set * batch;
    /*int max_thread = 1024;*/

    //Create complex variables on host
    printf("malloc input and output\n");
    cufftComplex *host_data_input = (cufftComplex *)malloc(size_of_data);
    /*cufftComplex *host_data_kernel = (cufftComplex *)malloc(size_of_one_set);*/
    cufftComplex *host_data_output = (cufftComplex *)malloc(size_of_one_set);

    /*// FIXME add this to end of input data, how do you arrange to be done in batches*/
    /*for ( int i = 0; i < N_kernel; i++)*/
    /*{ // Initialize the transform memory */
        /*host_data_kernel[i].x = hostF[i];*/
        /*host_data_kernel[i].y = 0.0f;*/
    /*}*/

    printf("initialize input and output\n");
    // FIXME do this in par on kernel
    for ( int i = 0; i < N; i++)
    { // Initialize the transform memory 
        host_data_input[i].x = hostI[i];
        host_data_input[i].y = 0.0f; // y is complex component

        host_data_output[i].x = 0.0f;
        host_data_output[i].y = 0.0f;
    }

    // Set GPU's to use 
    int deviceNum[nGPUs];
    for(int i = 0; i<nGPUs; ++i)
    {
        deviceNum[i] = i;
    }


    // Launch CUDA kernel to convert to complex
    /*cudaSetDevice(deviceNum[0]);*/
    /*initialize<<<N / max_thread + 1, max_thread>>>(N, hostI, u, u_fft);*/

    /*// Synchronize GPUs before moving forward*/
    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*cudaDeviceSynchronize();*/
    /*}*/

    // Initialize CUFFT for multiple GPUs //
    // Initialize result variable used for error checking
    cufftResult result;

    // Create empty plan that will be used for FFT / IFFT
    cufftHandle plan_forward_2_gpus, plan_inverse_1_gpu;
    result = cufftCreate(&plan_forward_2_gpus);
    if (result != CUFFT_SUCCESS) { printf ("*Create plan failed\n"); return 1; }
    result = cufftCreate(&plan_inverse_1_gpu);
    if (result != CUFFT_SUCCESS) { printf ("*Create inverse plan failed\n"); return 1; }

    // Tell cuFFT which GPUs to use
    result = cufftXtSetGPUs (plan_forward_2_gpus, nGPUs, deviceNum);
    if (result != CUFFT_SUCCESS) { printf ("*XtSetGPUs failed: code %i\n", result); return 1; }

    // Initializes the worksize variable
    size_t *worksize;                                   
    // Allocates memory for the worksize variable, which tells cufft how many GPUs it has to work with
    worksize =(size_t*)malloc(sizeof(size_t) * nGPUs);  
    
    printf("Make plans\n");
    // Create the plan for cufft, each element of worksize is the workspace for that GPU
    // multi-gpus must have a complex to complex transform
    /*int istride, idist, ostride, odist;*/
    /*istride = NULL, idist = NULL, ostride = NULL, odist = NULL;*/
    result = cufftMakePlanMany(plan_forward_2_gpus, rank, size, 
            NULL, (int) NULL, (int) NULL, 
            NULL, (int) NULL, (int) NULL, 
            CUFFT_C2C, batch, worksize); 
    if (result != CUFFT_SUCCESS) { printf ("*MakePlanMany* failed: code %d \n",(int)result); exit (EXIT_FAILURE) ; }


    /*printf("The size of the worksize is %lu\n", worksize[0]);*/

    printf("Allocate mGPU\n");
    // Initialize transform array - to be split among GPU's and transformed in place using cufftX
    cudaLibXtDesc *device_data_input;
    // Allocate data on multiple gpus using the cufft routines
    result = cufftXtMalloc(plan_forward_2_gpus, &device_data_input, CUFFT_XT_FORMAT_INPLACE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMalloc failed, code: %d\n", result); exit (EXIT_FAILURE) ; }

    printf("cudaMalloc\n");
    // set up mem to transfer to one GPU
    cufftComplex *GPU0_data_from_GPU1;
    int device0 = device_data_input->descriptor->GPUs[0];
    cudaSetDevice(device0);
    cudaError_t cuda_status;
    cuda_status = cudaMallocHost ((void **) &GPU0_data_from_GPU1, size_of_one_set);
    if (cuda_status != 0) { printf ("*cudaMallocHost  failed %s\n", cudaGetErrorString(cuda_status)); exit (EXIT_FAILURE); }

    printf("Xt memcpy\n");
    // Copy the data from 'host' to device using cufftXt formatting
    result = cufftXtMemcpy(plan_forward_2_gpus, device_data_input, host_data_input, CUFFT_COPY_HOST_TO_DEVICE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed, code: %d\n",result); exit (EXIT_FAILURE); }

    // Perform FFT on multiple GPUs
    printf("Forward 3d FFT on multiple GPUs\n");
    result = cufftXtExecDescriptorC2C(plan_forward_2_gpus, device_data_input, device_data_input, CUFFT_FORWARD);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecC2C  failed\n"); exit (EXIT_FAILURE); }

    // must be destroyed to free enough memory for inverse
    result = cufftDestroy(plan_forward_2_gpus);
    if (result != CUFFT_SUCCESS) { printf ("cufftDestroy failed: code %d\n",(int)result); exit (EXIT_FAILURE); }

    // transfer to one gpu for matrix multiply
    cufftComplex *device_data_on_GPU1;
    device_data_on_GPU1 = (cufftComplex*) (device_data_input->descriptor->data[1]);
    cuda_status = cudaMemcpy (GPU0_data_from_GPU1, device_data_on_GPU1, size_of_one_set,
            cudaMemcpyDeviceToDevice);
    if (cuda_status != 0) { printf ("*cudaMallocHost  failed %s\n", cudaGetErrorString(cuda_status)); exit (EXIT_FAILURE); }

    // multiply both ffts and scale output
    cufftComplex *device_data_on_GPU0;
    device_data_on_GPU0 = (cufftComplex*) (device_data_input->descriptor->data[0]);
    cudaSetDevice(device0); // do the computation on the first device
    /*FIXME is N the proper size to pass?*/
    ComplexPointwiseMulAndScale<<<32, 256>>>((cufftComplex*) device_data_on_GPU0, (cufftComplex*) GPU0_data_from_GPU1, N, 1.0f / (float) N);
    /*scaleResult<<<N / max_thread + 1, max_thread>>>(N, u_fft);*/

    result = cufftMakePlan3d(plan_inverse_1_gpu, size[0], size[1], size[2], CUFFT_C2C, worksize); 
    if (result != CUFFT_SUCCESS) { printf ("*MakePlan3d* failed: code %d \n",(int)result); exit (EXIT_FAILURE) ; }

    // Perform inverse FFT on multiple GPUs
    printf("Inverse 3d FFT on multiple GPUs\n");
    result = cufftExecC2C(plan_inverse_1_gpu, GPU0_data_from_GPU1, GPU0_data_from_GPU1, CUFFT_INVERSE);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecC2C  failed\n"); exit (EXIT_FAILURE); }

     /*Copy the output data from multiple gpus to the 'host' result variable (automatically reorders the data from output to natural order)*/
    cuda_status = cudaMemcpy (host_data_output, GPU0_data_from_GPU1, size_of_one_set, cudaMemcpyDeviceToHost);
    if (cuda_status != 0) { printf ("*cudaMemcpy  failed %s\n", cudaGetErrorString(cuda_status)); exit (EXIT_FAILURE); }


    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*idx = i*NX_per_GPU*NY*NZ;                // sets the index value of the data to send to each gpu*/
        /*scaleResult<<<gridSize, blockSize>>>(NX_per_GPU, &u_fft[idx]);*/
    /*}*/

    /*// Synchronize GPUs*/
    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*cudaDeviceSynchronize();*/
    /*}*/

    // Free malloc'ed variables
    free(worksize);
    // Free malloc'ed variables
    free(host_data_input);
    /*free(host_data_kernel);*/
    free(host_data_output);
    cudaFreeHost(GPU0_data_from_GPU1);

    /*FIXME free properly*/

    // Free cufftX malloc'ed variables
    result = cufftXtFree(device_data_input);
    if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }
    // Destroy FFT plan
    result = cufftDestroy(plan_inverse_1_gpu);
    if (result != CUFFT_SUCCESS) { printf ("cufftDestroy failed: code %d\n",(int)result); exit (EXIT_FAILURE); }

    return 0;

}

// Compute pad length per given dimension lengths
int get_pad_idxs(int m, int n) {
    return m + n - 1;
}

int conv_handler(float* hostI, float* hostF, float* hostO, int algo, int* size, int* filterdimA, int pad, int benchmark) {
    // hardcoded, func only supports 3D convolutions
    int nGPUs;
    cudaGetDeviceCount(&nGPUs);

    long N = size[0] * size[1] * size[2];
    if (benchmark)
        printf("Using %d GPUs on a %dx%dx%d grid, N:%d\n",nGPUs, size[0], size[1], size[2], N);
    long N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    long size_of_data = N * sizeof(cufftComplex);


    if (pad) {
        // Compute pad lengths
        int pad_lengths[3] = {0, 0, 0};
        for (int i=0; i < 3; i++) 
            pad_length[i] = cufftutils::get_pad_idxs(size[i], filterdimA[i]);

        int trim_idxs[3][1] = {{0, 0}, {0, 0}, {0, 0}};
        for (int i=0; i < 3; i++) {
            trim_idxs[i][0] = ceil((filterdimA[i] - 1) / 2);
            trim_idxs[i][1] = size[i] + ceil((filterdimA[i] - 1) / 2) - 1;
        }
        long N_padded = pad_lengths[0] * pad_lengths[1] * pad_lengths[2];
        size_of_data = N_padded * sizeof(cufftComplex);

    }

    //Create complex variables on host
    if (benchmark)
        printf("malloc input and output\n");
    cufftComplex *host_data_input = (cufftComplex *)malloc(size_of_data);
    if (!host_data_input) { printf("malloc input failed"); }
    cufftComplex *host_data_kernel = (cufftComplex *)malloc(size_of_data);
    if (!host_data_kernel) { printf("malloc kernel failed"); }


    float elapsed = 0.0f;
    cudaEvent_t start, stop;
    if (benchmark) {
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start, 0);
    }

    if (benchmark)
        printf("Initialize input and output updated\n");

    if (pad) {
        // Place in padded matrix, transform to column major order
        for ( long i = 0; i < pad_lengths[0]; i++) { 
            for (long j = 0; j < pad_lengths[1]; j++) {
                for (long k = 0; k < pad_lengths[2]; k++) {
                    long column_ord_idx = k + j * size[2] + i * size[2] * size[1];
                    long c_ord_idx = i + j * size[0] + k * size[0] * size[1];
                    if (column_ord_idx < N_kernel) {
                        /*printf("hostf[i]: %.2f, i: %d", hostF[i], i);*/
                        host_data_kernel[c_ord_idx].x = hostF[column_ord_idx];
                    } else {
                        host_data_kernel[c_ord_idx].x = 0.0f;
                    }
                    host_data_kernel[c_ord_idx].y = 0.0f; // y is complex component

                    // convert from Matlab Column-order to C-order
                    if (column_ord_idx < N) {
                        host_data_input[c_ord_idx].x = hostI[column_ord_idx];
                    } else {
                        host_data_input[c_ord_idx].x = 0.0f;
                    }
                    host_data_input[c_ord_idx].y = 0.0f; 
                }
            }
        }
    } else {
        for ( long i = 0; i < N; i++)
        { // Initialize the transform memory 
            if (i < N_kernel) {
                /*printf("hostf[i]: %.2f, i: %d", hostF[i], i);*/
                host_data_kernel[i].x = hostF[i];
            } else {
                host_data_kernel[i].x = 0.0f;
            }
            host_data_kernel[i].y = 0.0f; // y is complex component

            host_data_input[i].x = hostI[i];
            host_data_input[i].y = 0.0f; 
        }
    }

    if (benchmark)
        printf("Input and output successfully initialized\n");

    // Set GPU's to use 
    int deviceNum[nGPUs];
    for(int i = 0; i<nGPUs; ++i)
    {
        deviceNum[i] = i;
    }

    // Launch custom CUDA kernel to convert to complex
    /*cudaSetDevice(deviceNum[0]);*/
    /*initialize<<<N / max_thread + 1, max_thread>>>(N, hostI, u, u_fft);*/

    /*// Synchronize GPUs before moving forward*/
    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*cudaDeviceSynchronize();*/
    /*}*/

    // Initialize result variable used for error checking
    cufftResult result;

    // Create empty plan that will be used for FFT / IFFT
    cufftHandle plan_fft3;
    result = cufftCreate(&plan_fft3);
    if (result != CUFFT_SUCCESS) { printf ("*Create plan failed\n"); return 1; }

    // Tell cuFFT which GPUs to use
    result = cufftXtSetGPUs (plan_fft3, nGPUs, deviceNum);
    if (result != CUFFT_SUCCESS) { printf ("*XtSetGPUs failed: code %i\n", result); return 1; }

    // Initializes the worksize variable
    size_t *worksize;                                   
    // Allocates memory for the worksize variable, which tells cufft how many GPUs it has to work with
    worksize =(size_t*)malloc(sizeof(size_t) * nGPUs);  
    
    if (benchmark)
        printf("Make plan 3d\n");
    // Create the plan for cufft, each element of worksize is the workspace for that GPU
    // multi-gpus must have a complex to complex transform
    result = cufftMakePlan3d(plan_fft3, size[0], size[1], size[2], CUFFT_C2C, worksize); 
    if (result != CUFFT_SUCCESS) { printf ("*MakePlan3d* failed: code %d \n",(int)result); exit (EXIT_FAILURE) ; }


    // Allocate data on multiple gpus using the cufft routines
    // Initialize transform array - to be split among GPU's and transformed in place using cufftX
    if (benchmark)
        printf("Allocate mGPU\n");
    cudaLibXtDesc *device_data_input, *device_data_kernel, *input_natural, *kernel_natural;
    result = cufftXtMalloc(plan_fft3, &device_data_input, CUFFT_XT_FORMAT_INPLACE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMalloc failed, code: %d\n", result); exit (EXIT_FAILURE) ; }
    result = cufftXtMalloc(plan_fft3, &device_data_kernel, CUFFT_XT_FORMAT_INPLACE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMalloc kernel failed, code: %d\n", result); exit (EXIT_FAILURE) ; }
    result = cufftXtMalloc(plan_fft3, &input_natural, CUFFT_XT_FORMAT_INPLACE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMalloc input natural failed, code: %d\n", result); exit (EXIT_FAILURE) ; }
    result = cufftXtMalloc(plan_fft3, &kernel_natural, CUFFT_XT_FORMAT_INPLACE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMalloc output natural failed, code: %d\n", result); exit (EXIT_FAILURE) ; }

    if (benchmark)
        printf("Xt memcpy\n");
    // Copy the data from 'host' to device using cufftXt formatting
    result = cufftXtMemcpy(plan_fft3, device_data_input, host_data_input, CUFFT_COPY_HOST_TO_DEVICE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed, code: %d\n",result); exit (EXIT_FAILURE); }
    result = cufftXtMemcpy(plan_fft3, device_data_kernel, host_data_kernel, CUFFT_COPY_HOST_TO_DEVICE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed, code: %d\n",result); exit (EXIT_FAILURE); }

    // Perform FFT on multiple GPUs
    if (benchmark)
        printf("Forward 3d FFT input on multiple GPUs\n");
    result = cufftXtExecDescriptorC2C(plan_fft3, device_data_input, device_data_input, CUFFT_FORWARD);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecC2C input failed\n"); exit (EXIT_FAILURE); }
    result = cufftXtExecDescriptorC2C(plan_fft3, device_data_kernel, device_data_kernel, CUFFT_FORWARD);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecC2C kernel failed\n"); exit (EXIT_FAILURE); }

    // cufftXtMemcpy() - Copy the data to natural order on GPUs
    result = cufftXtMemcpy (plan_fft3, input_natural, device_data_input, CUFFT_COPY_DEVICE_TO_DEVICE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed\n"); exit (EXIT_FAILURE) ; }
    result = cufftXtMemcpy (plan_fft3, kernel_natural, device_data_kernel, CUFFT_COPY_DEVICE_TO_DEVICE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed\n"); exit (EXIT_FAILURE) ; }

    // multiply both ffts and scale output
    if (benchmark)
        printf("Matrix Multiply on multiple GPUs\n");
    for (int i = 0; i<nGPUs; ++i){
        cudaSetDevice(deviceNum[i]);
        cufftComplex *input_data_on_gpu, *kernel_data_on_gpu;
        input_data_on_gpu = (cufftComplex*) (input_natural->descriptor->data[deviceNum[i]]);
        kernel_data_on_gpu = (cufftComplex*) (kernel_natural->descriptor->data[deviceNum[i]]);
        // multiply, scale both arrays, keep product inplace on device_data_input cudaLibXtDesc
        //FIXME size to pass?
        int size_device = int(input_natural->descriptor->size[deviceNum[i]] / sizeof(cufftComplex));
        ComplexPointwiseMulAndScale<<<32, 256>>>((cufftComplex*) kernel_data_on_gpu, (cufftComplex*) input_data_on_gpu, size_device, 1.0f / (float) N);
    }

    // Synchronize GPUs
    for (int i = 0; i<nGPUs; ++i){
        cudaSetDevice(deviceNum[i]);
        cudaDeviceSynchronize();
        /*getCudaLastError("Kernel executuion failed in PointwiseMulAndScale");*/
    }

    // Perform inverse FFT on multiple GPUs
    if (benchmark)
        printf("Inverse 3d FFT on multiple GPUs\n");
    result = cufftXtExecDescriptorC2C(plan_fft3, device_data_input, device_data_input, CUFFT_INVERSE);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecDesc inverse failed, code: %d\n",result); exit (EXIT_FAILURE); }

    if (benchmark) {
        cudaEventRecord(stop, 0);
        cudaDeviceSynchronize();
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&elapsed, start, stop);
        cudaEventDestroy(start);
        cudaEventDestroy(stop);
        printf(" Full convolution cost %.2f ms\n", elapsed);
    }

     /*Copy the output data from multiple gpus to the 'host' result variable (automatically reorders the data from output to natural order)*/
    /*result = cufftXtMemcpy (plan_fft3, host_data_output, device_data_input, CUFFT_COPY_DEVICE_TO_HOST);*/
    result = cufftXtMemcpy (plan_fft3, host_data_input, device_data_input, CUFFT_COPY_DEVICE_TO_HOST);
    if (result != CUFFT_SUCCESS) { printf ("*cufftXtMemcpy failed, code: %d\n",result); exit (EXIT_FAILURE); }

    if (benchmark)
        printf("Place results in output\n");
    for ( long i = 0; i < N; i++)
    { // Initialize the transform memory 
        hostO[i] = host_data_input[i].x;
    }
    if (benchmark)
        printf("in place successful\n");

    // Free malloc'ed variables
    free(worksize);
    // Free malloc'ed variables
    free(host_data_input);
    free(host_data_kernel);
    /*free(host_data_output);*/

    // Destroy FFT plan
    // must be destroyed to free enough memory for inverse
    result = cufftDestroy(plan_fft3);
    if (result != CUFFT_SUCCESS) { printf ("cufftDestroy failed: code %d\n",(int)result); exit (EXIT_FAILURE); }

    // Free cufftX malloc'ed variables
    result = cufftXtFree(device_data_input);
    if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }
    result = cufftXtFree(device_data_kernel);
    if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }
    result = cufftXtFree(input_natural);
    if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }
    result = cufftXtFree(kernel_natural);
    if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }

    return 0;
}

int fft3(float * data, int* size, int* length) {
     
    int nGPUs;
    cudaGetDeviceCount(&nGPUs);
    printf("No. of GPU on node %d\n", nGPUs);

    /*FIXME account for length*/
    int i, j, k, idx;
    int N = size[0] * size[1] * size[2];
    /*int max_thread = 1024;*/

    //Create complex variables on host
    cufftComplex *u = (cufftComplex *)malloc(sizeof(cufftComplex) * N);
    cufftComplex *u_fft = (cufftComplex *)malloc(sizeof(cufftComplex) * N);

    // Initialize the transform memory 
    for ( int i = 0; i < N; i++)
    {
        u[i].x = data[i];
        u[i].y = 0.0f;

        u_fft[i].x = 0.0f;
        u_fft[i].y = 0.0f;
    }

    // Set GPU's to use and list device properties
    int deviceNum[nGPUs];
    for(i = 0; i<nGPUs; ++i)
    {
        deviceNum[i] = i;
    }

    /*printf("Running Multi_GPU_FFT_check using %d GPUs on a %dx%dx%d grid.\n",nGPUs, size[0], size[1], size[2]);*/

    // Launch CUDA kernel to convert to complex
    /*cudaSetDevice(deviceNum[0]);*/
    /*initialize<<<N / max_thread + 1, max_thread>>>(N, data, u, u_fft);*/

    /*// Synchronize GPUs before moving forward*/
    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*cudaDeviceSynchronize();*/
    /*}*/

    /*float elapsed = 0.0f;*/
    /*cudaEvent_t start, stop;*/
    /*cudaEventCreate(&start);*/
    /*cudaEventCreate(&stop);*/
    /*cudaEventRecord(start, 0);*/

    // Initialize CUFFT for multiple GPUs //
    // Initialize result variable used for error checking
    cufftResult result;

    // Create empty plan that will be used for the FFT
    cufftHandle plan;
    result = cufftCreate(&plan);
    if (result != CUFFT_SUCCESS) { printf ("*Create failed\n"); return 1; }

    // Tell cuFFT which GPUs to use
    result = cufftXtSetGPUs (plan, nGPUs, deviceNum);
    if (result != CUFFT_SUCCESS) { printf ("*XtSetGPUs failed: code %i\n", result); return 1; }

    // Create the plan for the FFT
    // Initializes the worksize variable
    size_t *worksize;                                   
    // Allocates memory for the worksize variable, which tells cufft how many GPUs it has to work with
    worksize =(size_t*)malloc(sizeof(size_t) * nGPUs);  
    
    // Create the plan for cufft, each element of worksize is the workspace for that GPU
    // multi-gpus must have a complex to complex transform
    result = cufftMakePlan3d(plan, size[0], size[1], size[2], CUFFT_C2C, worksize); 
    if (result != CUFFT_SUCCESS) { printf ("*MakePlan* failed: code %d \n",(int)result); exit (EXIT_FAILURE) ; }

    /*printf("The size of the worksize is %lu\n", worksize[0]);*/

    // Initialize transform array - to be split among GPU's and transformed in place using cufftX
    cudaLibXtDesc *device_data_input;
    // Allocate data on multiple gpus using the cufft routines
    result = cufftXtMalloc(plan, (cudaLibXtDesc **)&device_data_input, CUFFT_XT_FORMAT_INPLACE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMalloc failed, code: %d\n", result); exit (EXIT_FAILURE) ; }

    // Copy the data from 'host' to device using cufftXt formatting
    result = cufftXtMemcpy(plan, device_data_input, u, CUFFT_COPY_HOST_TO_DEVICE);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed, code: %d\n",result); exit (EXIT_FAILURE); }

    // Perform FFT on multiple GPUs
    printf("Forward 3d FFT on multiple GPUs\n");
    result = cufftXtExecDescriptorC2C(plan, device_data_input, device_data_input, CUFFT_FORWARD);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecC2C  failed\n"); exit (EXIT_FAILURE); }

    /*cudaEventRecord(stop, 0);*/
    /*cudaEventSynchronize(stop);*/
    /*cudaEventElapsedTime(&elapsed, start, stop);*/
    /*cudaEventDestroy(start);*/
    /*cudaEventDestroy(stop);*/
    /*printf("1 FFTs cost %.2f ms\n", elapsed);*/

    // Perform inverse FFT on multiple GPUs
    printf("Inverse 3d FFT on multiple GPUs\n");
    result = cufftXtExecDescriptorC2C(plan, device_data_input, device_data_input, CUFFT_INVERSE);
    if (result != CUFFT_SUCCESS) { printf ("*XtExecC2C  failed\n"); exit (EXIT_FAILURE); }

    // Copy the output data from multiple gpus to the 'host' result variable (automatically reorders the data from output to natural order)
    result = cufftXtMemcpy (plan, u_fft, device_data_input, CUFFT_COPY_DEVICE_TO_HOST);
    if (result != CUFFT_SUCCESS) { printf ("*XtMemcpy failed\n"); exit (EXIT_FAILURE); }

    // Scale output to match input (cuFFT does not automatically scale FFT output by 1/N)
    cudaSetDevice(deviceNum[0]);

    // cuFFT does not scale transform to 1 / N 
    for (int idx=0; idx < N; idx++) {
        u_fft[idx].x = u_fft[idx].x / ( (float)N );
        u_fft[idx].y = u_fft[idx].y / ( (float)N );
    }

    /*scaleResult<<<N / max_thread + 1, max_thread>>>(N, u_fft);*/

    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*idx = i*NX_per_GPU*NY*NZ;                // sets the index value of the data to send to each gpu*/
        /*scaleResult<<<gridSize, blockSize>>>(NX_per_GPU, &u_fft[idx]);*/
    /*}*/

    /*// Synchronize GPUs*/
    /*for (i = 0; i<nGPUs; ++i){*/
        /*cudaSetDevice(deviceNum[i]);*/
        /*cudaDeviceSynchronize();*/
    /*}*/

    // Test results to make sure that u = u_fft
    float error = 0.0;
    for (i = 0; i<size[0]; ++i){
        for (j = 0; j<size[1]; ++j){
            for (k = 0; k<size[2]; ++k){
                idx = k + j*size[2] + size[2]*size[1]*i;
                // error += (float)u[idx].x - sin(x)*cos(y)*cos(z);
                error += abs((float)u[idx].x - (float)u_fft[idx].x);
                // printf("At idx = %d, the value of the error is %f\n",idx,(float)u[idx].x - (float)u_fft[idx].x);
                // printf("At idx = %d, the value of the error is %f\n",idx,error);

            }
        }
    }
    printf("The sum of the error is %4.4g\n",error);

    // Deallocate variables

    // Free malloc'ed variables
    free(worksize);
    // Free cuda malloc'ed variables
    cudaFree(u);
    cudaFree(u_fft);
    // Free cufftX malloc'ed variables
    result = cufftXtFree(device_data_input);
    if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }
    // result = cufftXtFree(u_reorder);
    // if (result != CUFFT_SUCCESS) { printf ("*XtFree failed\n"); exit (EXIT_FAILURE); }
    // Destroy FFT plan
    result = cufftDestroy(plan);
    if (result != CUFFT_SUCCESS) { printf ("cufftDestroy failed: code %d\n",(int)result); exit (EXIT_FAILURE); }

    return 0;
}

} // namespace cufftutils

int main (int argc, char** argv)
{
    int size[3] = {2048, 2048, 500};
    int filterdimA[3] = {10, 10, 10};
    int benchmark = 1;
    /*int dims = 3;*/
    /*if (argc) {*/
        /*while (dims) {*/
            /*size[dims - 1] = atol(argv[dims - 1]);*/
            /*filterdimA[dims + 2] = atol(argv[dims + 2]);*/
            /*dims--;*/
        /*}*/
        /*benchmark = atol(argv[6]);*/
    /*} */
    int algo = 1;
    int result = 0;
    /*int size[3] = {512, 512, 512};*/
    int N = size[0] * size[1] * size[2];
    int N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    
    printf("Initializing sin array\n");
    float* data = new float[N]; 
    float* kernel = new float[N]; 

    for (int i=0; i < N; i++)
        data[i] = sin(i);

    printf("Sin array created\n");

    printf("Initializing kernel\n");
    for (int i=0; i < N_kernel; i++)
        kernel[i] = sin(i);

    printf("Kernel created\n");

    printf("Testing convolution\n");
    result = cufftutils::conv_handler(data, kernel, data, algo, size,
            filterdimA, pad, benchmark);

    /*printf("Testing fft\n");*/
    /*result = fft3(data, size, size);*/

    return result;
}

