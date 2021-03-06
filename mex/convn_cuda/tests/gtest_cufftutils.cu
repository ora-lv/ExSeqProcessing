#include "gtest/gtest.h"

#include "cufftutils.h"
#include <complex.h>
/*#include <cuda_runtime.h>*/
#include <cufft.h>
#include <cufftXt.h>
#include "error_helper.h"
#include "cuda_timer.h"
/*#include <cuda.h>*/

#include <vector>
#include <cstdint>
#include <random>
#include <cmath>

class ConvnCufftTest : public ::testing::Test {
protected:
    ConvnCufftTest() {
    }
    virtual ~ConvnCufftTest() {
    }
};

static void initImageVal(float* image, int imageSize, float val) {
    for (int index = 0; index < imageSize; index++) {
        image[index] = val;
    }
}

//Generate uniform numbers [0,1)
static void initImage(float* image, int imageSize) {
    /*static unsigned seed = 123456789;*/
    for (int index = 0; index < imageSize; index++) {
        /*seed = ( 1103515245 * seed + 12345 ) & 0xffffffff;*/
        /*image[index] = float(seed)*2.3283064e-10; //2^-32*/
        image[index] = (float) index;
        //image[index] = (float) sin(index); //2^-32
        //printf("image(index) %.4f\n", image[index]);
    }
}

void matrix_is_zero(float* first, unsigned int* size, bool column_order, int benchmark, float tol)  {
    //convert back to original then check the two matrices
    long long idx;
    for (int i = 0; i<size[0]; ++i) {
        for (int j = 0; j<size[1]; ++j) {
            for (int k = 0; k<size[2]; ++k) {
                idx = cufftutils::convert_idx(i, j, k, size, column_order);
                /*if (benchmark)*/
                    /*printf("idx:%d\n", idx);*/
                ASSERT_NEAR(first[idx], 0.0, tol);
            }
            /*if (benchmark)*/
                /*printf("\n");*/
        }
    }
}

void matrix_is_equal_complex(cufftComplex* first, cufftComplex* second, unsigned int* size, bool column_order, 
        int benchmark, float tol)  {
    //convert back to original then check the two matrices
    long long idx;
    for (int i = 0; i<size[0]; ++i) {
        for (int j = 0; j<size[1]; ++j) {
            for (int k = 0; k<size[2]; ++k) {
                idx = cufftutils::convert_idx(i, j, k, size, column_order);
                if (benchmark)
                    printf("checking idx:%d...\n", idx);
                ASSERT_NEAR(first[idx].x, second[idx].x, tol);
                ASSERT_NEAR(first[idx].y, second[idx].y, tol);
            }
            if (benchmark)
                printf("\n");
        }
    }
}

void matrix_is_equal(float* first, float* second, unsigned int* size, bool column_order, 
        int benchmark, float tol)  {
    //convert back to original then check the two matrices
    long long idx;
    for (int i = 0; i<size[0]; ++i) {
        for (int j = 0; j<size[1]; ++j) {
            for (int k = 0; k<size[2]; ++k) {
                idx = cufftutils::convert_idx(i, j, k, size, column_order);
                if (benchmark)
                    printf("idx=%d (%d, %d, %d): %f %f\n",idx, i, j, k, first[idx], second[idx]);
                ASSERT_NEAR(first[idx], second[idx], tol);
            }
        }
    }
}

__global__
void print_thread() {
    printf("threadIdx.x=%d\n", threadIdx.x);
}

TEST_F(ConvnCufftTest, DISABLED_FFTInverseBasicTest) {

    unsigned int size[3] = {50, 50, 5};
    unsigned int filterdimA[3] = {5, 5, 5};
    int N = size[0] * size[1] * size[2];
    int N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    
    //printf("Initializing cufft sin array\n");
    float* data = new float[N]; 
    float* kernel = new float[N_kernel]; 

    //printf("Sin array created\n");
    for (int i=0; i < N; i++)
        data[i] = sin(i);

    //printf("Initializing kernel\n");
    for (int i=0; i < N_kernel; i++)
        kernel[i] = sin(i);
    int nGPUs;
    cudaGetDeviceCount(&nGPUs);
    printf("No. of GPU on node %d\n", nGPUs);

    int i, j, k, idx;

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

    // Create empty plan that will be used for the FFT
    cufftHandle plan;
    cufftSafeCall(cufftCreate(&plan));

    // Tell cuFFT which GPUs to use
    cufftSafeCall(cufftXtSetGPUs (plan, nGPUs, deviceNum));

    // Create the plan for the FFT
    // Initializes the worksize variable
    size_t *worksize;                                   
    // Allocates memory for the worksize variable, which tells cufft how many GPUs it has to work with
    worksize =(size_t*)malloc(sizeof(size_t) * nGPUs);  
    
    // Create the plan for cufft, each element of worksize is the workspace for that GPU
    // multi-gpus must have a complex to complex transform
    cufftSafeCall(cufftMakePlan3d(plan, size[0], size[1], size[2], CUFFT_C2C, worksize)); 

    /*printf("The size of the worksize is %lu\n", worksize[0]);*/

    // Initialize transform array - to be split among GPU's and transformed in place using cufftX
    cudaLibXtDesc *device_data_input;
    // Allocate data on multiple gpus using the cufft routines
    cufftSafeCall(cufftXtMalloc(plan, (cudaLibXtDesc **)&device_data_input, CUFFT_XT_FORMAT_INPLACE));

    // Copy the data from 'host' to device using cufftXt formatting
    cufftSafeCall(cufftXtMemcpy(plan, device_data_input, u, CUFFT_COPY_HOST_TO_DEVICE));

    // Perform FFT on multiple GPUs
    printf("Forward 3d FFT on multiple GPUs\n");
    cufftSafeCall(cufftXtExecDescriptorC2C(plan, device_data_input, device_data_input, CUFFT_FORWARD));

    // Perform inverse FFT on multiple GPUs
    printf("Inverse 3d FFT on multiple GPUs\n");
    cufftSafeCall(cufftXtExecDescriptorC2C(plan, device_data_input, device_data_input, CUFFT_INVERSE));

    // Copy the output data from multiple gpus to the 'host' result variable (automatically reorders the data from output to natural order)
    cufftSafeCall(cufftXtMemcpy (plan, u_fft, device_data_input, CUFFT_COPY_DEVICE_TO_HOST));

    // Scale output to match input (cuFFT does not automatically scale FFT output by 1/N)
    cudaSetDevice(deviceNum[0]);

    // cuFFT does not scale transform to 1 / N 
    for (int idx=0; idx < N; idx++) {
        u_fft[idx].x = u_fft[idx].x / ( (float)N );
        u_fft[idx].y = u_fft[idx].y / ( (float)N );
    }

    // Test results to make sure that u = u_fft
    float error = 0.0;
    float tol = 2;
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
    ASSERT_NEAR(error, 0.0, tol);

    // Deallocate variables

    // Free malloc'ed variables
    free(worksize);
    // Free cuda malloc'ed variables
    cudaFree(u);
    cudaFree(u_fft);
    // Free cufftX malloc'ed variables
    cufftSafeCall(cufftXtFree(device_data_input));
    // cufftSafeCall(cufftXtFree(u_reorder));
    // Destroy FFT plan
    cufftSafeCall(cufftDestroy(plan));
}

TEST_F(ConvnCufftTest, DISABLED_PrintDeviceDataTest) {
    long long N = 10;
    long long size_of_data = sizeof(cufftComplex)*N;

    cufftComplex* device_data_input;
    cudaMalloc(&device_data_input, size_of_data);
    cufftComplex *host_data_input = (cufftComplex *)malloc(size_of_data);

    for (int i=0; i < N; i++) {
        host_data_input[i].x = i;
        host_data_input[i].y = i;
    }
    cudaMemcpy(device_data_input, host_data_input, size_of_data, cudaMemcpyHostToDevice);

    cufftutils::printHostData(host_data_input, N);
    cufftutils::printDeviceData(device_data_input, N);

    free(host_data_input);
    cudaFree(device_data_input);
}

TEST_F(ConvnCufftTest, ConvnCompare1GPUTest) {
    int benchmark = 0;
    unsigned int size[3] = {31, 31, 5};
    unsigned int filterdimA[3] = {2, 2, 2};
    bool column_order = false;
    int algo = 1;
    float tol = 1;
    int N = size[0] * size[1] * size[2];
    int N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    if (benchmark)
        printf("size %d, %d, %d\n", size[0], size[1], size[2]);
    
    float* hostI = new float[N]; 
    float* hostO = new float[N]; 
    float* hostO_1GPU = new float[N]; 
    float* hostF = new float[N_kernel]; 

    initImageVal(hostI, N, 0.0f);
    initImageVal(hostF, N_kernel, 0.0f);

    if (benchmark)
        printf("mGPU convolution\n");
    cufftutils::conv_handler(hostI, hostF, hostO, algo, size,
            filterdimA, column_order, benchmark);
    if (benchmark)
        printf("Check with 1GPU convolution\n");
    cufftutils::conv_1GPU_handler(hostI, hostF, hostO_1GPU, algo, size,
            filterdimA, column_order, benchmark);

    matrix_is_zero(hostO, size, column_order, 0, tol);
    matrix_is_zero(hostO_1GPU, size, column_order, 0, tol);
    matrix_is_equal(hostO, hostO_1GPU, size, column_order, benchmark, tol);

    if (benchmark)
        printf("Check with sin values");
    initImage(hostI, N);
    initImage(hostF, N_kernel);

    if (benchmark)
        printf("mGPU convolution\n");
    cufftutils::conv_handler(hostI, hostF, hostO, algo, size,
            filterdimA, column_order, benchmark);
    if (benchmark)
        printf("Check with 1GPU convolution\n");
    cufftutils::conv_1GPU_handler(hostI, hostF, hostO_1GPU, algo, size,
            filterdimA, column_order, benchmark);

    matrix_is_equal(hostO, hostO_1GPU, size, column_order, benchmark, tol);
}

TEST_F(ConvnCufftTest, DeviceInitInputsTest) {
    int benchmark = 0;
    // minimum acceptable size for cufft functions
    unsigned int size[3] = {31, 31, 5};
    unsigned int filterdimA[3] = {2, 2, 2};
    bool column_order = false;
    int N = size[0] * size[1] * size[2];
    int N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    
    float* hostI = new float[N]; 
    float* hostF = new float[N_kernel]; 
    float* hostI_column = new float[N]; 
    float* hostF_column = new float[N_kernel]; 

    // Create two random images
    initImage(hostI, N);
    initImage(hostF, N_kernel);

    // copy the matrices into column order for comparison
    if (benchmark)
        printf("Matrix conversions\n");
    cufftutils::convert_matrix(hostI, hostI_column, size, column_order);
    cufftutils::convert_matrix(hostF, hostF_column, filterdimA, column_order);

    if (benchmark) {
        printf("\nhostF:%d\n", N_kernel);
        for (int i = 0; i < N_kernel; i++)
            printf("hostF[%d]=%.3f\n", i, hostF[i]);
        printf("\nhostF_column:%d\n", N_kernel);
        for (int i = 0; i < N_kernel; i++)
            printf("hostF_column[%d]=%.3f\n", i, hostF_column[i]);
    }

    unsigned int pad_size[3];
    int trim_idxs[3][2];
    cufftutils::get_pad_trim(size, filterdimA, pad_size, trim_idxs);

    if (benchmark) {
        printf("size %d, %d, %d\n", size[0], size[1], size[2]);
        printf("pad_size %d, %d, %d\n", pad_size[0], pad_size[1], pad_size[2]);
        for (int i=0; i < 3; i++) 
            printf("trim_idxs[%d]=%d, %d\n", i, trim_idxs[i][0], trim_idxs[i][1]);
    }
    long long N_padded = pad_size[0] * pad_size[1] * pad_size[2];
    long long size_of_data = N_padded * sizeof(cufftComplex);
    long long float_size = N* sizeof(float);
    long long kernel_float_size = N_kernel* sizeof(float);

    if (benchmark)
        printf("cudaMalloc\n");
    float* devI, *devF, *devI_column, *devF_column;
    cudaMalloc(&devI, float_size); cudaCheckPtr(devI);
    cudaMalloc(&devF, kernel_float_size); cudaCheckPtr(devF);

    cudaMalloc(&devI_column, float_size); cudaCheckPtr(devI_column);
    cudaMalloc(&devF_column, kernel_float_size); cudaCheckPtr(devF_column);

    if (benchmark)
        printf("cudaMemcpy\n");
    // Copy the data from 'host' to device using cufftXt formatting
    cudaSafeCall(cudaMemcpy(devI, hostI, float_size, cudaMemcpyHostToDevice));
    cudaSafeCall(cudaMemcpy(devF, hostF, kernel_float_size, cudaMemcpyHostToDevice));
    cudaSafeCall(cudaMemcpy(devI_column, hostI_column, float_size, cudaMemcpyHostToDevice));
    cudaSafeCall(cudaMemcpy(devF_column, hostF_column, kernel_float_size, cudaMemcpyHostToDevice));

    int nGPUs;
    cudaGetDeviceCount(&nGPUs);

    // Set GPU's to use 
    int deviceNum[nGPUs];
    for(int i = 0; i<nGPUs; ++i)
    {
        deviceNum[i] = i;
    }

    // declare empty plan that will be used for FFT / IFFT
    cufftHandle plan_fft3;
    cufftSafeCall(cufftCreate(&plan_fft3));

    // Tell cuFFT which GPUs to use
    cufftSafeCall(cufftXtSetGPUs (plan_fft3, nGPUs, deviceNum));

    // Allocates memory for the worksize variable, which tells cufft how many GPUs it has to work with
    size_t *worksize;                                   
    worksize =(size_t*)malloc(sizeof(size_t) * nGPUs);  
    
    // Create the plan for cufft, each element of worksize is the workspace for that GPU
    // multi-gpus must have a complex to complex transform
    cufftSafeCall(cufftMakePlan3d(plan_fft3, pad_size[0], pad_size[1], pad_size[2], CUFFT_C2C, worksize)); 

    // Allocate data on multiple gpus using the cufft routines
    // Initialize transform array - to be split among GPU's and transformed in place using cufftX
    cudaLibXtDesc *device_data_input, *device_data_kernel;
    cufftSafeCall(cufftXtMalloc(plan_fft3, &device_data_input, CUFFT_XT_FORMAT_INPLACE));
    cufftSafeCall(cufftXtMalloc(plan_fft3, &device_data_kernel, CUFFT_XT_FORMAT_INPLACE));

    cufftComplex *input_data_on_gpu, *kernel_data_on_gpu, *input_data_on_gpu_column, *kernel_data_on_gpu_column;
    cudaMalloc(&input_data_on_gpu, size_of_data); cudaCheckPtr(input_data_on_gpu);
    cudaMalloc(&kernel_data_on_gpu, size_of_data); cudaCheckPtr(kernel_data_on_gpu);
    cudaMalloc(&input_data_on_gpu_column, size_of_data); cudaCheckPtr(input_data_on_gpu_column);
    cudaMalloc(&kernel_data_on_gpu_column, size_of_data); cudaCheckPtr(kernel_data_on_gpu_column);

    long long start = 0;
    long long blockSize = 32;
    long long gridSize;
    gridSize = (N_padded + blockSize - 1) / blockSize; // round up
    ASSERT_GE(gridSize * blockSize, N_padded);
    if (benchmark)
        printf("N_padded: %lld, gridSize: %d\n", N_padded, gridSize);

    cufftutils::initialize_inputs_1GPU<<<gridSize, blockSize>>>(devI, devF, input_data_on_gpu, 
            kernel_data_on_gpu, N_padded, start, size[0], size[1], size[2], pad_size[0], pad_size[1], 
            pad_size[2], filterdimA[0], filterdimA[1], filterdimA[2], column_order, benchmark);
    cudaCheckError();

    cudaSafeCall(cudaDeviceSynchronize());

    // Initialize data from device to device LibXtDescriptor using cufftXt formatting
    int starts[nGPUs];
    cufftComplex *host_data_input = (cufftComplex *) malloc(size_of_data);
    cudaCheckPtr(host_data_input);
    cufftComplex *host_data_kernel = (cufftComplex *) malloc(size_of_data);
    cudaCheckPtr(host_data_kernel);
    for (int i = 0; i<nGPUs; ++i){

        long long size_device = long(device_data_input->descriptor->size[deviceNum[i]] / sizeof(cufftComplex));
        long long size_device_kernel = long(device_data_kernel->descriptor->size[deviceNum[i]] / sizeof(cufftComplex));
        ASSERT_EQ(size_device_kernel, size_device);

        starts[i] = start;
        start += size_device;
    }
    ASSERT_EQ(start, N_padded);

    for (int i = 0; i<nGPUs; ++i) {
        cudaSafeCall(cudaMemcpy(host_data_input + starts[i], input_data_on_gpu + starts[i],
                    device_data_input->descriptor->size[deviceNum[i]],
                    cudaMemcpyDeviceToHost));
        cudaSafeCall(cudaMemcpy(host_data_kernel + starts[i],
                    kernel_data_on_gpu + starts[i],
                    device_data_kernel->descriptor->size[deviceNum[i]],
                    cudaMemcpyDeviceToHost));
        if (benchmark) {
            printf("start[%d]=%d, length:%d\n", i, starts[i],
                    device_data_input->descriptor->size[deviceNum[i]] / sizeof(cufftComplex)); 
            cufftutils::printHostData(host_data_input + starts[i], device_data_input->descriptor->size[deviceNum[i]] / sizeof(cufftComplex));
        }
    }

    // Allocate data on multiple gpus using the cufft routines
    // Initialize transform array - to be split among GPU's and transformed in place using cufftX
    cudaLibXtDesc *device_data_input_column, *device_data_kernel_column;
    cufftSafeCall(cufftXtMalloc(plan_fft3, &device_data_input_column, CUFFT_XT_FORMAT_INPLACE));
    cufftSafeCall(cufftXtMalloc(plan_fft3, &device_data_kernel_column, CUFFT_XT_FORMAT_INPLACE));

    // Initialize data from device to device LibXtDescriptor using cufftXt formatting
    start = 0;
    cufftComplex *host_data_input_column = (cufftComplex *)malloc(size_of_data);
    cudaCheckPtr(host_data_input_column);
    cufftComplex *host_data_kernel_column = (cufftComplex *)malloc(size_of_data);
    cudaCheckPtr(host_data_kernel_column);

    cufftutils::initialize_inputs_1GPU<<<gridSize, blockSize>>>(devI_column, devF_column, input_data_on_gpu_column, 
            kernel_data_on_gpu_column, N_padded, start, size[0], size[1], size[2], pad_size[0], pad_size[1], 
            pad_size[2], filterdimA[0], filterdimA[1], filterdimA[2], !column_order, benchmark);
    cudaCheckError();

    cudaSafeCall(cudaDeviceSynchronize());

    for (int i = 0; i<nGPUs; ++i){
        long long size_device = long(device_data_input_column->descriptor->size[deviceNum[i]] / sizeof(cufftComplex));

        ASSERT_GE(gridSize * blockSize, size_device);
        if (benchmark)
            printf("size_device: %lld, gridSize: %d, start: %d\n", size_device, gridSize, start);

        starts[i] = start;
        start += size_device;
    }
    ASSERT_EQ(start, N_padded);

    if (benchmark)
        printf("Copy back to host for error checking");

    // Synchronize GPUs for column
    for (int i = 0; i<nGPUs; ++i){
        cudaSafeCall(cudaMemcpy(host_data_input_column + starts[i], input_data_on_gpu_column + starts[i], device_data_input_column->descriptor->size[deviceNum[i]], cudaMemcpyDeviceToHost));
        cudaSafeCall(cudaMemcpy(host_data_kernel_column + starts[i], kernel_data_on_gpu_column + starts[i], device_data_kernel_column->descriptor->size[deviceNum[i]], cudaMemcpyDeviceToHost));
    }

    if (benchmark) {
        /*printf("\nhost_data_input elements:%d\n", N_padded);*/
        /*cufftutils::printHostData(host_data_input, N_padded);*/
        printf("\nhost_data_input elements:%d\n", N_padded);
        cufftutils::printHostData(host_data_input, N_padded);

        /*printf("\nhost_data_input_column elements:%d\n", N_padded);*/
        /*cufftutils::printHostData(host_data_input_column, N_padded);*/
        /*printf("\nhost_data_kernel_column elements:%d\n", N_padded);*/
        /*cufftutils::printHostData(host_data_kernel_column, N_padded);*/
    }

    // Check that initialize inputs put both row and column ordered matrix into c-order
    matrix_is_equal_complex(host_data_input, host_data_input_column, size, 
            column_order, 0, 0.0); //tol=0.0 means exactly equal
    matrix_is_equal_complex(host_data_kernel, host_data_kernel_column, size, 
            column_order, 0, 0.0);

    /*// test padding is correct for c-order*/
    long long idx;
    long long pad_idx;
    long long idx_filter;
    for (int i = 0; i<pad_size[0]; ++i) {
        for (int j = 0; j<pad_size[1]; ++j) {
            for (int k = 0; k<pad_size[2]; ++k) {
                idx = cufftutils::convert_idx(i, j, k, size, column_order);
                idx_filter = cufftutils::convert_idx(i, j, k, filterdimA, column_order);
                // we always place into c-order for processing in initialize_inputs_1GPU
                pad_idx = cufftutils::convert_idx(i, j, k, pad_size, false);

                if (benchmark) {
                    printf("pad_idx=%lld idx=%lld idx_filter=%lld (%d %d %d) | ",
                            pad_idx, idx, idx_filter, i, j, k);
                }

                if ((i < size[0]) && (j < size[1]) && (k < size[2]) ) {
                    ASSERT_EQ(host_data_input[pad_idx].x, hostI[idx]);
                } else {
                    ASSERT_EQ(host_data_input[pad_idx].x, 0.0f);
                }
                ASSERT_EQ(host_data_input[pad_idx].y, 0.0f);

                if ((i < filterdimA[0]) && (j < filterdimA[1]) && (k < filterdimA[2])) {
                    ASSERT_EQ(host_data_kernel[pad_idx].x, hostF[idx_filter]);
                } else {
                    ASSERT_EQ(host_data_kernel[pad_idx].x, 0.0f);
                }
                ASSERT_EQ(host_data_kernel[pad_idx].y, 0.0f);
            }
            if (benchmark)
                printf("\n");
        }
    }

    delete[] hostI;
    delete[] hostF;
    free(host_data_input);
    free(host_data_kernel);
    cudaFree(devI);
    cudaFree(devF);
    cudaFree(devI_column);
    cudaFree(devF_column);
    cudaSafeCall(cudaFree(input_data_on_gpu));
    cudaSafeCall(cudaFree(input_data_on_gpu_column));
    cudaSafeCall(cudaFree(kernel_data_on_gpu));
    cudaSafeCall(cudaFree(kernel_data_on_gpu_column));

    // Destroy FFT plan
    cufftSafeCall(cufftDestroy(plan_fft3));

    // Free cufftX malloc'ed variables
    cufftSafeCall(cufftXtFree(device_data_input));
    cufftSafeCall(cufftXtFree(device_data_kernel));
}

TEST_F(ConvnCufftTest, InitializePadTestGPU) {
    int benchmark = 0;
    unsigned int size[3] = {31, 31, 5};
    /*unsigned int size[3] = {1024, 1024, 126};*/
    unsigned int filterdimA[3] = {2, 2, 2};
    bool column_order = true;
    int N = size[0] * size[1] * size[2];
    int N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    
    float* hostI = new float[N]; 
    float* hostF = new float[N_kernel]; 
    float* hostI_column = new float[N]; 
    float* hostF_column = new float[N_kernel]; 

    // Create two random images
    initImage(hostI, N);
    initImage(hostF, N_kernel);

    if (benchmark)
        printf("Matrix conversions\n");
    cufftutils::convert_matrix(hostI, hostI_column, size, column_order);
    cufftutils::convert_matrix(hostF, hostF_column, filterdimA, column_order);

    if (benchmark) {
        printf("\nhostI:%d\n", N);
        for (int i = 0; i < N; i++)
            printf("hostI[%d]=%.3f\n", i, hostI[i]);
        printf("\nhostI_column:%d\n", N);
        for (int i = 0; i < N; i++)
            printf("hostI_column[%d]=%.3f\n", i, hostI_column[i]);
    }


    unsigned int pad_size[3];
    int trim_idxs[3][2];
    cufftutils::get_pad_trim(size, filterdimA, pad_size, trim_idxs);

    if (benchmark) {
        printf("size %d, %d, %d\n", size[0], size[1], size[2]);
        printf("pad_size %d, %d, %d\n", pad_size[0], pad_size[1], pad_size[2]);
        for (int i=0; i < 3; i++) 
            printf("trim_idxs[%d]=%d, %d\n", i, trim_idxs[i][0], trim_idxs[i][1]);
    }
    long long N_padded = pad_size[0] * pad_size[1] * pad_size[2];
    long long size_of_data = N_padded * sizeof(cufftComplex);
    long long float_size = N* sizeof(float);
    long long kernel_float_size = N_kernel* sizeof(float);

    if (benchmark)
        printf("cudaMalloc\n");
    float* devI, *devF, *devI_column, *devF_column;
    cudaMalloc(&devI, float_size); cudaCheckPtr(devI);
    cudaMalloc(&devF, kernel_float_size); cudaCheckPtr(devF);

    cudaMalloc(&devI_column, float_size); cudaCheckPtr(devI_column);
    cudaMalloc(&devF_column, kernel_float_size); cudaCheckPtr(devF_column);

    if (benchmark)
        printf("cudaMemcpy\n");
    // Copy the data from 'host' to device using cufftXt formatting
    cudaSafeCall(cudaMemcpy(devI, hostI, float_size, cudaMemcpyHostToDevice));
    cudaSafeCall(cudaMemcpy(devF, hostF, kernel_float_size, cudaMemcpyHostToDevice));
    cudaSafeCall(cudaMemcpy(devI_column, hostI_column, float_size, cudaMemcpyHostToDevice));
    cudaSafeCall(cudaMemcpy(devF_column, hostF_column, kernel_float_size, cudaMemcpyHostToDevice));

    cufftComplex *input_data_on_gpu, *kernel_data_on_gpu, *input_data_on_gpu_column, *kernel_data_on_gpu_column;
    cudaMalloc(&input_data_on_gpu, size_of_data); cudaCheckPtr(input_data_on_gpu);
    cudaMalloc(&kernel_data_on_gpu, size_of_data); cudaCheckPtr(kernel_data_on_gpu);
    cudaMalloc(&input_data_on_gpu_column, size_of_data); cudaCheckPtr(input_data_on_gpu_column);
    cudaMalloc(&kernel_data_on_gpu_column, size_of_data); cudaCheckPtr(kernel_data_on_gpu_column);
    long long start = 0;

    long long blockSize = 32;
    long long gridSize;
    gridSize = (N_padded + blockSize - 1) / blockSize; // round up
    ASSERT_GE(gridSize * blockSize, N_padded);
    if (benchmark)
        printf("N_padded: %lld, gridSize: %d\n", N_padded, gridSize);

    cufftutils::initialize_inputs_1GPU<<<gridSize, blockSize>>>(devI, devF, input_data_on_gpu, 
            kernel_data_on_gpu, N_padded, start, size[0], size[1], size[2], pad_size[0], pad_size[1], 
            pad_size[2], filterdimA[0], filterdimA[1], filterdimA[2], column_order, benchmark);
    cudaCheckError();

    cudaSafeCall(cudaDeviceSynchronize());

    //passing column order should still output c-order data
    cufftutils::initialize_inputs_1GPU<<<gridSize, blockSize>>>(devI_column, devF_column, input_data_on_gpu_column, 
            kernel_data_on_gpu_column, N_padded, start, size[0], size[1], size[2], pad_size[0], pad_size[1], 
            pad_size[2], filterdimA[0], filterdimA[1], filterdimA[2], !column_order, benchmark);
    cudaCheckError();

    cudaSafeCall(cudaDeviceSynchronize());

    cufftComplex *host_data_input = (cufftComplex *) malloc(size_of_data);
    cudaCheckPtr(host_data_input);
    cufftComplex *host_data_input_column = (cufftComplex *) malloc(size_of_data);
    cudaCheckPtr(host_data_input_column);
    cufftComplex *host_data_kernel = (cufftComplex *) malloc(size_of_data);
    cudaCheckPtr(host_data_kernel);
    cufftComplex *host_data_kernel_column = (cufftComplex *) malloc(size_of_data);
    cudaCheckPtr(host_data_kernel_column);

    cudaSafeCall(cudaMemcpy(host_data_input, input_data_on_gpu,
                size_of_data, cudaMemcpyDeviceToHost));
    cudaSafeCall(cudaMemcpy(host_data_input_column, input_data_on_gpu_column,
                size_of_data, cudaMemcpyDeviceToHost));
    cudaSafeCall(cudaMemcpy(host_data_kernel, kernel_data_on_gpu,
                size_of_data, cudaMemcpyDeviceToHost));
    cudaSafeCall(cudaMemcpy(host_data_kernel_column, kernel_data_on_gpu_column,
                size_of_data, cudaMemcpyDeviceToHost));

    if (benchmark) {
        printf("\nhost_data_input elements:%d\n", N_padded);
        cufftutils::printHostData(host_data_input, N_padded);
        /*printf("\nhost_data_kernel elements:%d\n", N_padded);*/
        /*cufftutils::printHostData(host_data_kernel, N_padded);*/

        /*printf("\nhost_data_input_column elements:%d\n", N_padded);*/
        /*cufftutils::printHostData(host_data_input_column, N_padded);*/
        /*printf("\nhost_data_kernel_column elements:%d\n", N_padded);*/
        /*cufftutils::printHostData(host_data_kernel_column, N_padded);*/
    }

    // Check that initialize inputs put both row and column ordered matrix into c-order
    matrix_is_equal_complex(host_data_input, host_data_input_column, size, 
            column_order, 0, 0.0);
    matrix_is_equal_complex(host_data_kernel, host_data_kernel_column, size, 
            column_order, 0, 0.0);

    // test padding is correct for c-order
    long long idx;
    long long pad_idx;
    long long idx_filter;
    for (int i = 0; i<pad_size[0]; ++i) {
        for (int j = 0; j<pad_size[1]; ++j) {
            for (int k = 0; k<pad_size[2]; ++k) {
                idx = cufftutils::convert_idx(i, j, k, size, column_order);
                idx_filter = cufftutils::convert_idx(i, j, k, filterdimA, column_order);
                pad_idx = cufftutils::convert_idx(i, j, k, pad_size, false);

                if (benchmark) {
                    printf("pad_idx=%d idx=%d (%d %d %d) %.3f | ",
                            pad_idx, idx, i, j, k, (int) host_data_input[pad_idx].x);
                }

                if ((i < size[0]) && (j < size[1]) && (k < size[2]) ) {
                    ASSERT_EQ(host_data_input[pad_idx].x, hostI[idx]);
                } else {
                    ASSERT_EQ(host_data_input[pad_idx].x, 0.0f);
                }
                ASSERT_EQ(host_data_input[pad_idx].y, 0.0f);

                if ((i < filterdimA[0]) && (j < filterdimA[1]) && (k < filterdimA[2])) {
                    ASSERT_EQ(host_data_kernel[pad_idx].x, hostF[idx_filter]);
                } else {
                    ASSERT_EQ(host_data_kernel[pad_idx].x, 0.0f);
                }
                ASSERT_EQ(host_data_kernel[pad_idx].y, 0.0f);

            }
            if (benchmark)
                printf("\n");
        }
    }
    delete[] hostI;
    delete[] hostF;
    free(host_data_input);
    free(host_data_kernel);

    cudaSafeCall(cudaFree(devI));
    cudaSafeCall(cudaFree(devF));
    cudaSafeCall(cudaFree(devI_column));
    cudaSafeCall(cudaFree(devF_column));
    cudaSafeCall(cudaFree(input_data_on_gpu));
    cudaSafeCall(cudaFree(input_data_on_gpu_column));
    cudaSafeCall(cudaFree(kernel_data_on_gpu));
    cudaSafeCall(cudaFree(kernel_data_on_gpu_column));
}

TEST_F(ConvnCufftTest, DISABLED_1GPUConvnFullImageTest) {
    unsigned int size[3] = {1024, 1024, 126};
    unsigned int filterdimA[3] = {5, 5, 5};
    int benchmark = 0;
    bool column_order = false;
    int algo = 1;
    float tol = .0001;
    long long N = size[0] * size[1] * size[2];
    long long N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    
    float* data = new float[N]; 
    float* kernel = new float[N_kernel]; 

    initImage(data, N); 
    initImageVal(kernel, N_kernel, 0.0); //kernel of zeros

    cufftutils::conv_1GPU_handler(data, kernel, data, algo, size,
            filterdimA, column_order, benchmark);

    matrix_is_zero(data, size, column_order, benchmark, tol);
}

TEST_F(ConvnCufftTest, TrimPadTest) {
    int benchmark = 0;
    // minimum acceptable size for cufft functions
    unsigned int size[3] = {31, 31, 5};
    unsigned int filterdimA[3] = {2, 2, 2};
    bool column_order = false;
    int N = size[0] * size[1] * size[2];
    
    float* hostO = new float[N]; 

    // Create sequential image for ease of debug
    initImage(hostO, N);

    unsigned int pad_size[3];
    int trim_idxs[3][2];
    cufftutils::get_pad_trim(size, filterdimA, pad_size, trim_idxs);

    if (benchmark) {
        printf("size %d, %d, %d\n", size[0], size[1], size[2]);
        printf("pad_size %d, %d, %d\n", pad_size[0], pad_size[1], pad_size[2]);
        for (int i=0; i < 3; i++) 
            printf("trim_idxs[%d]=%d, %d\n", i, trim_idxs[i][0], trim_idxs[i][1]);
    }
    long long N_padded = pad_size[0] * pad_size[1] * pad_size[2];
    long long size_of_data = N_padded * sizeof(cufftComplex);
    long long float_size = N* sizeof(float);

    cufftComplex *host_data_input = (cufftComplex *) malloc(size_of_data);
    float *transferO = (float *) malloc(float_size);
    for (int i = 0; i < N_padded; i++) {
        host_data_input[i].x = (float) i;
        host_data_input[i].y = (float) 0;
    }

    if (benchmark)
        printf("cudaMalloc\n");
    float* deviceO;
    cufftComplex *device_data_input; 
    cudaMalloc(&device_data_input, size_of_data); cudaCheckPtr(device_data_input);
    cudaMalloc(&deviceO, float_size); cudaCheckPtr(deviceO);

    if (benchmark)
        printf("cudaMemcpy\n");
    // Copy the data from 'host' to device using cufftXt formatting
    cudaSafeCall(cudaMemcpy(device_data_input, host_data_input, size_of_data, cudaMemcpyHostToDevice));

    if (benchmark)
        printf("trim_pad\n");
    CudaTimer timer;
    cufftutils::trim_pad(trim_idxs, size, pad_size, column_order, hostO, host_data_input, 0);
    if (benchmark) {
        printf("trim_pad elapsed %.4f s\n", timer.get_laptime());
        timer.reset();
    }

    int blockSize = 256;
    if (benchmark) {
        printf("trim_pad_1GPU\n");
        printf("blockSize:%d\n", blockSize);
    }
    cufftutils::trim_pad_1GPU<<<(N_padded + blockSize - 1) / blockSize, blockSize>>>(trim_idxs[0][0],
            trim_idxs[0][1], trim_idxs[1][0], trim_idxs[1][1], trim_idxs[2][0],
            trim_idxs[2][1], size[0], size[1], size[2], pad_size[0],
            pad_size[1], pad_size[2], N_padded, column_order, deviceO, device_data_input,
            benchmark);
    if (benchmark) {
        printf("trim_pad_1GPU elapsed %.4f s\n", timer.get_laptime());
        timer.reset();
    }

    cudaSafeCall(cudaMemcpy(transferO, deviceO, float_size, cudaMemcpyDeviceToHost));

    if (benchmark) {
        printf("\nhostO elements:%d\n", N);
          for (int i = 0; i < N; i++)
            printf("[%d]=%.3f\n", i, hostO[i]);
        printf("\ntransferO elements:%d\n", N);
          for (int i = 0; i < N; i++)
            printf("[%d]=%.3f\n", i, transferO[i]);
    }

    matrix_is_equal(hostO, transferO, size, column_order, benchmark, 0.0);

    free(hostO);
    free(transferO);
    cudaSafeCall(cudaFree(device_data_input));
    cudaSafeCall(cudaFree(deviceO));
}

TEST_F(ConvnCufftTest, ConvnFullImageTest) {
    unsigned int size[3] = {1024, 1024, 126};
    unsigned int filterdimA[3] = {5, 5, 5};
    int benchmark = 0;
    bool column_order = true;
    int algo = 1;
    float tol = .0001;
    long long N = size[0] * size[1] * size[2];
    long long N_kernel = filterdimA[0] * filterdimA[1] * filterdimA[2];
    
    float* data = new float[N]; 
    float* kernel = new float[N_kernel]; 

    initImage(data, N); 
    initImageVal(kernel, N_kernel, 0.0); //kernel of zeros

    cufftutils::conv_handler(data, kernel, data, algo, size,
            filterdimA, column_order, benchmark);

    matrix_is_zero(data, size, column_order, 0, tol);
}

TEST_F(ConvnCufftTest, ConvnColumnOrderingTest) {

    // generate params
    int benchmark = 0;
    float tol = .8;
    int algo = 0;
    bool column_order = false;
    unsigned int size[3] = {31, 31, 5};
    unsigned int filterdimA[] = {2, 2, 2};
    int filtersize = filterdimA[0]*filterdimA[1]*filterdimA[2];
    int insize = size[0]*size[1]*size[2];

    // Create a random filter and image
    float* hostI;
    float* hostF;
    float* hostI_column;
    float* hostF_column;
    float* hostO;
    float* hostO_column;

    hostI = new float[insize];
    hostF = new float[filtersize];
    hostI_column = new float[insize];
    hostF_column = new float[filtersize];
    hostO = new float[insize];
    hostO_column = new float[insize];

    // Create two random images
    initImage(hostI, insize);
    initImage(hostF, filtersize);

    if (benchmark)
        printf("Matrix conversions\n");
    cufftutils::convert_matrix(hostI, hostI_column, size, column_order);
    cufftutils::convert_matrix(hostF, hostF_column, filterdimA, column_order);

    if (benchmark) {
        printf("\nhostF elements:%d\n", filtersize);
        for (int i = 0; i < filtersize; i++)
            printf("%.1f\n", hostF[i]);
        printf("\nhostF_column elements:%d\n", filtersize);
        for (int i = 0; i < filtersize; i++)
            printf("%.1f\n", hostF_column[i]);
    }

    if (benchmark)
        printf("\n\noriginal order:%d\n", column_order);
    cufftutils::conv_handler(hostI, hostF, hostO, algo, size, 
            filterdimA, column_order, benchmark);

    if (benchmark)
        printf("\n\ntest with column_order\n", !column_order);
    cufftutils::conv_handler(hostI_column, hostF_column, hostO_column, 
            algo, size, filterdimA, !column_order, benchmark);

    //convert back to original then check the two matrices
    long long idx;
    long long col_idx;
    float val;
    for (int i = 0; i<size[0]; ++i) {
        for (int j = 0; j<size[1]; ++j) {
            for (int k = 0; k<size[2]; ++k) {
                idx = cufftutils::convert_idx(i, j, k, size, column_order);
                col_idx = cufftutils::convert_idx(i, j, k, size, !column_order);
                if (benchmark) {
                    val = hostO_column[col_idx]; // get the real component
                    printf("idx=%d (%d, %d, %d): %f | ", idx, i, j, k, val);
                }
                ASSERT_NEAR(hostO[idx], hostO_column[col_idx], tol);
            }
            if (benchmark)
                printf("\n");
        }
    }


}

