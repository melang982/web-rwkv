struct View {
    stride: vec4<u32>,
    offset: vec4<u32>,
    shape: vec4<u32>,  
};

@group(0) @binding(0) var<uniform> shape: vec4<u32>;                        // [C, T, B]
@group(0) @binding(1) var<uniform> view: View;                              // [C, 4, B] / [C, 5L, B]
@group(0) @binding(2) var<uniform> mask: u32;                               // [B]

@group(0) @binding(3) var<storage, read> time_decay: array<vec4<f32>>;      // (C)
@group(0) @binding(4) var<storage, read> time_first: array<vec4<f32>>;      // (C)

@group(0) @binding(5) var<storage, read> x: array<vec4<f32>>;               // (B, T, C)
@group(0) @binding(6) var<storage, read> k: array<vec4<f32>>;               // (B, T, C)
@group(0) @binding(7) var<storage, read> v: array<vec4<f32>>;               // (B, T, C)
@group(0) @binding(8) var<storage, read> r: array<vec4<f32>>;               // (B, T, C)

@group(0) @binding(9) var<storage, read_write> output: array<vec4<f32>>;    // (B, T, C)
@group(0) @binding(10) var<storage, read_write> state: array<vec4<f32>>;    // (B, 4, C)

const BLOCK_SIZE: u32 = 128u;

fn compute_index(batch: u32, token: u32, index: u32) -> u32 {
    let stride = view.stride.x / 4u;
    let offset = view.offset.x / 4u;
    return ((view.offset.z + batch) * view.stride.y + view.offset.y + token) * stride + offset + index;
}

fn batch_masked(batch: u32) -> bool {
    return ((mask >> batch) & 1u) == 0u;
}

@compute @workgroup_size(128, 1, 1)
fn token_mix(@builtin(global_invocation_id) invocation_id: vec3<u32>) {
    let stride = shape[0] / 4u;
    let index = invocation_id.x;
    let batch = invocation_id.z;
    let masked = batch_masked(batch);

    if index >= stride || batch >= shape[2] {
        return;
    }

    let xi = compute_index(batch, 0u, index);
    let ai = compute_index(batch, 1u, index);
    let bi = compute_index(batch, 2u, index);
    let pi = compute_index(batch, 3u, index);

    if !masked {
        state[xi] = x[(batch * shape[1] + (shape[1] - 1u)) * stride + index];
    }

    for (var t = 0u; t < shape[1]; t += 1u) {
        let bti = (batch * shape[1] + t) * stride + index;

        let kk = k[bti];
        let vv = v[bti];

        let aa = state[ai];
        let bb = state[bi];
        let pp = state[pi];
        var ww = time_first[index] + kk;
        var q = max(pp, ww);
        var e1 = exp(pp - q);
        var e2 = exp(ww - q);

        let rr = 1.0 / (1.0 + exp(-r[bti]));
        output[bti] = rr * (e1 * aa + e2 * vv) / (e1 * bb + e2);

        ww = time_decay[index] + pp;
        q = max(ww, kk);
        e1 = exp(ww - q);
        e2 = exp(kk - q);

        if !masked {
            state[ai] = e1 * aa + e2 * vv;
            state[bi] = e1 * bb + e2;
            state[pi] = q;
        }
    }
}