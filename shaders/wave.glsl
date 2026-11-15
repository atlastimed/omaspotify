// Three ribbons of the same spectrum, read at different scales so they move
// together without tracing the same line. Each mirrors about a midline.

// The midline runs through the middle of the room, and the loudest ribbon
// just fills it.

void main() {
  vec2 px = qt_TexCoord0 * area;
  float x = px.x / area.x;
  vec2 space = room();
  float from = px.y - (space.x + space.y * 0.5);
  float reach = space.y * 0.44;
  vec3 rgb = vec3(0.0);
  float alpha = 0.0;
  for (float layer = 0.0; layer < 3.0; layer += 1.0) {
    // The back ribbons read a stretched, drifting copy of the spectrum.
    float drift = sin(time * (0.35 + layer * 0.17) + layer * 2.1) * 0.035 * layer;
    float at = bandAt(clamp(x + drift, 0.0, 1.0)) * (1.0 - layer * 0.16) + layer * 1.7;
    float swell = 0.04 * sin(x * (5.0 + layer * 3.0) + time * (0.9 - layer * 0.25));
    float level = curve(at) * (1.0 - layer * 0.2) + swell * (0.3 + bass);
    float edge = clamp(level, 0.0, 1.0) * reach + 1.5;
    float d = abs(from) - edge;
    float fill = (1.0 - smoothstep(-1.0, 1.0, d)) * (0.2 - layer * 0.045);
    float line = exp(-abs(d) / (1.2 + layer * 0.5)) * (0.95 - layer * 0.25);
    float halo = exp(-max(d, 0.0) / (8.0 + 34.0 * glow)) * glow * (0.32 - layer * 0.07)
      * (0.3 + level);
    vec3 tone = palette(clamp(level * 1.15 + layer * 0.22, 0.0, 1.0));
    float seen = clamp(fill + line + halo, 0.0, 1.0);
    rgb += tone * seen * (1.0 - alpha);
    alpha += seen * (1.0 - alpha);
  }
  fragColor = lit(alpha > 0.0 ? rgb / alpha : rgb, alpha);
}
