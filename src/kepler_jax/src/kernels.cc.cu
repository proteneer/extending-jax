#include "kepler.h"
#include "kernel_helpers.h"
#include "kernels.h"

namespace kepler_jax {

namespace {

template <typename Scalar>
__global__ void kepler_kernel(std::int64_t size, const Scalar *mean_anom, const Scalar *ecc,
                              Scalar *sin_ecc_anom, Scalar *cos_ecc_anom) {
  for (std::int64_t idx = blockIdx.x * blockDim.x + threadIdx.x; idx < size;
       idx += blockDim.x * gridDim.x) {
    compute_eccentric_anomaly<Scalar>(mean_anom[idx], ecc[idx], sin_ecc_anom + idx,
                                      cos_ecc_anom + idx);
  }
}

void ThrowIfError(cudaError_t error) {
  if (error != cudaSuccess) {
    throw std::runtime_error(cudaGetErrorString(error));
  }
}

template <typename T>
inline void apply_kepler(const std::int64_t size, cudaStream_t stream, void **buffers) {
  const T *mean_anom = reinterpret_cast<const T *>(buffers[0]);
  const T *ecc = reinterpret_cast<const T *>(buffers[1]);
  T *sin_ecc_anom = reinterpret_cast<T *>(buffers[2]);
  T *cos_ecc_anom = reinterpret_cast<T *>(buffers[3]);

  const int block_dim = 128;
  const int grid_dim = std::min<int>(1024, (size + block_dim - 1) / block_dim);
  kepler_kernel<T>
      <<<grid_dim, block_dim, 0, stream>>>(size, mean_anom, ecc, sin_ecc_anom, cos_ecc_anom);

  ThrowIfError(cudaGetLastError());
}

}  // namespace

void gpu_kepler(cudaStream_t stream, void **buffers, const char *opaque, std::size_t opaque_len) {
  const KeplerDescriptor &d = *UnpackDescriptor<KeplerDescriptor>(opaque, opaque_len);
  const std::int64_t size = d.size;

  // Dispatch based on the data type
  switch (d.dtype) {
    case kepler_jax::Type::F32:
      apply_kepler<float>(size, stream, buffers);
      break;
    case kepler_jax::Type::F64:
      apply_kepler<double>(size, stream, buffers);
      break;
  }
}

}  // namespace kepler_jax
