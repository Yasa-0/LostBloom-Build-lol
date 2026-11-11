#pragma header

uniform float time;
uniform float cameraZoom;

uniform int STARTING_LAYERS;
uniform bool flipY;
uniform bool pixely;
uniform float blurStrength;
uniform float wobbleStrength;

float hash(vec2 p){
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float rainLayer(vec2 uv, float layer)
{
    uv *= 8.0 + layer * 1.5;

    float id = floor(uv.x);
    float rnd = hash(vec2(id, layer));

    float x = fract(uv.x) - 0.5;
    x += (hash(vec2(id, layer)) - 0.5) * 0.3;

    float y = fract(uv.y + time * (2.8 + rnd * 2.5));

    // wide drops
    float drop = smoothstep(0.02, 0.0, abs(x) * (2.5 + rnd * 4.0));

    // short streaks
    drop *= smoothstep(0.2, 0.0, y);

    return drop;
}

void main()
{
    vec2 uv = openfl_TextureCoordv.xy;

    // =========================
    // WATER / BOIL DISTORTION
    // =========================
    vec2 wobble = vec2(
        sin(uv.y * 20.0 + time * 2.0),
        cos(uv.x * 20.0 + time * 2.0)
    );

    uv += wobble * wobbleStrength * 0.01;

    // =========================
    // CHEAP BLUR (5-TAP)
    // =========================
    vec2 texel = vec2(1.0 / openfl_TextureSize.x, 1.0 / openfl_TextureSize.y);

    vec4 blurCol = vec4(0.0);

    blurCol += flixel_texture2D(bitmap, uv);
    blurCol += flixel_texture2D(bitmap, uv + vec2(texel.x, 0.0));
    blurCol += flixel_texture2D(bitmap, uv - vec2(texel.x, 0.0));
    blurCol += flixel_texture2D(bitmap, uv + vec2(0.0, texel.y));
    blurCol += flixel_texture2D(bitmap, uv - vec2(0.0, texel.y));

    blurCol /= 5.0;

    vec4 base = blurCol;

    // =========================
    // RAIN UV SETUP (unchanged logic)
    // =========================
    vec2 centered = uv - 0.5;
    centered *= 1.0 / (cameraZoom + 1.0);

    if (flipY)
        centered.y *= -1.0;

    if (pixely)
        centered = floor(centered * 120.0) / 120.0;

    float rain = 0.0;

    for (int i = 0; i < 10; i++)
    {
        if (i < STARTING_LAYERS) continue;

        float fi = float(i);

        vec2 layerUV = centered * (1.0 + fi * 0.2);

        layerUV.x += (hash(vec2(fi, floor(time * 2.0))) - 0.5) * 0.6;

        rain += rainLayer(layerUV, fi);
    }

    rain = clamp(rain, 0.0, 1.0);

    // =========================
    // RAIN COMPOSITE
    // =========================
    vec3 rainCol = vec3(1.0) * rain;
    float alpha = rain * 0.12;

    base.rgb += rainCol * 0.2;
    base.a = max(base.a, alpha);

    gl_FragColor = base;
}