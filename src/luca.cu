#include "luca.h"

void processFrame(cv::Mat &frame, cv::VideoWriter &writer) {
    int originalType = frame.type();
    int originalStep = frame.step;
    frame.convertTo(frame, CV_32FC3);
    Npp32f *d_frame, *d_result_1;
    size_t pitch;

    // Allocate memory on the GPU, and copy the frame on it
    cudaMallocPitch(&d_frame, &pitch, 3 * frame.cols * sizeof(Npp32f), frame.rows);
    cudaMemcpy2D(d_frame, pitch, frame.ptr(), frame.step, 3 * frame.cols * sizeof(Npp32f), frame.rows, cudaMemcpyHostToDevice);

    // Allocate memory for the green channel and extract it
    Npp32f* d_greenChannel;
    size_t greenPitch;
    cudaMallocPitch(&d_result_1, &greenPitch, frame.cols * sizeof(Npp32f), frame.rows);
    cudaMallocPitch(&d_greenChannel, &greenPitch, frame.cols * sizeof(Npp32f), frame.rows);

    NppiSize oSizeROI;
    oSizeROI.width = frame.cols;
    oSizeROI.height = frame.rows;

    // Extract the green channel
    nppiCopy_32f_C3C1R(d_frame + 1, pitch, d_greenChannel, greenPitch, oSizeROI);

    // Edge detection using Scharr
    nppiFilterScharrHoriz_32f_C1R(d_greenChannel, greenPitch, d_result_1, greenPitch, oSizeROI);

    // Convert the single channel on device to a 3-channel grayscale image for OpenCV on the hot
    cv::Mat channelResult(frame.rows, frame.cols, CV_32FC1);
    cv::Mat grayscaleImage(frame.rows, frame.cols, originalType);

    cudaMemcpy2D(channelResult.ptr(), channelResult.step, d_result_1, greenPitch, frame.cols * sizeof(Npp32f), frame.rows, cudaMemcpyDeviceToHost);
    channelResult.convertTo(channelResult, CV_8UC1);
    cv::cvtColor(channelResult, grayscaleImage, cv::COLOR_GRAY2BGR);

    // Save the frame in hte video
    writer.write(grayscaleImage);

    // Deallocate
    cudaFree(d_frame);
    cudaFree(d_result_1);
}

__host__ int main(int argc, char** argv) {
    printf("Submission of Luca Venturi\n");

    if (argc != 3) {
        printf("This programs requires 2 parameters instead of %d: the source video and the output video.", argc);
        return 1;
    }

    cv::VideoCapture cap(argv[1]);
    if (!cap.isOpened()) {
        std::cerr << "Error: Could not open video." << std::endl;
        return -1;
    }

    int frame_width = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_WIDTH));
    int frame_height = static_cast<int>(cap.get(cv::CAP_PROP_FRAME_HEIGHT));
    double fps = cap.get(cv::CAP_PROP_FPS);

    cv::VideoWriter writer(argv[2], cv::VideoWriter::fourcc('m', 'p', '4', 'v'), fps, cv::Size(frame_width, frame_height));
    if (!writer.isOpened()) {
        std::cerr << "Error: Could not open destination video." << std::endl;
        return -1;
    }

    cv::Mat frame;
    int numFrame = 0;
    while (true) {
        // Read a new frame
        if (!cap.read(frame)) {
            break; // Break the loop if there are no more frames
        }

        printf("Frame %d\n", numFrame);
        numFrame++;

        processFrame(frame, writer);
    }
}