#include <memory>

#include "sift_bridge.h"
#include "sift.h"
#include "sift_types.h"
#include "cuda_task_executor.h"

#include "spdlog/spdlog.h"

namespace cudautils {

void sift_bridge(
        std::shared_ptr<spdlog::logger> logger,
        const unsigned int x_size,
        const unsigned int y_size,
        const unsigned int z_size,
        const unsigned int x_sub_size,
        const unsigned int y_sub_size,
        const unsigned int dx,
        const unsigned int dy,
        const unsigned int dw,
        const int num_gpus,
        const int num_streams,
        const double* in_image,
        const int8_t* in_map,
        cudautils::SiftParams sift_params,
        cudautils::Keypoint_store keystore) {

    std::shared_ptr<cudautils::Sift> ni =
        std::make_shared<cudautils::Sift>(x_size, y_size, z_size, x_sub_size,
                y_sub_size, dx, dy, dw, num_gpus, num_streams, sift_params);

    cudautils::CudaTaskExecutor executor(num_gpus, num_streams, ni);

    logger->info("setImage start");
    ni->setImage(in_image);
    logger->info("setImage end");
    ni->setMapToBeInterpolated(in_map);
    logger->info("setMap end");

    logger->info("calc start");
    executor.run();
    logger->info("calc end");

    logger->info("getImage start");
    ni->getKeystore(keystore);
    logger->info("getImage end");

}

}

