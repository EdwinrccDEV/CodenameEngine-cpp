#pragma header

// Used in charter by waveforms

#define HEIGHT      0.05   // Height of the Bar
#define BACKLIGHT   0.6    // Backlight
#define BRIGHTNESS  0.33   // overall Brightness
#define GLOW        1.25   // Glow intensity of the Bar

const vec3 gradient1 = vec3(114.0/255.0, 81.0/255.0, 135.0/255.0);
const vec3 gradient2 = vec3(144.0/255.0, 80.0/255.0, 186.0/255.0);

const vec4 outlinecolor = vec4(0.1);
const vec3 lowdetailcol = vec3(0.0, 0.0, 1.0);

uniform vec2 textureRes;
uniform float pixelOffset;

uniform float playerPosition;

uniform sampler2D waveformTexture;
uniform vec2 waveformSize;

uniform bool lowDetail;

uniform float time;

// Cada texel de la textura guarda 3 muestras seguidas, una por canal (R, G, B),
// asi que la celda y el canal salen del indice de muestra, no del texel.
float getSample(float cell) {
	float id = clamp(floor(cell), 0.0, waveformSize.x * waveformSize.y - 1.0);
	vec2 wavePixel = vec2(mod(id, waveformSize.x), floor(id / waveformSize.x));
	vec4 waveData = texture2D(waveformTexture, (wavePixel + 0.5) / waveformSize);

	float channel = mod(id, 3.0);
	if (channel < 1.0) return waveData.r;
	if (channel < 2.0) return waveData.g;
	return waveData.b;
}

float getAmplitude(vec2 pixel) {
	// Cada muestra ocupa 3 unidades de alto y esta centrada en 3k+1.5; se
	// interpola entre las dos vecinas para que la onda no salga escalonada.
	float cell = max((pixel.y + pixelOffset) / 3.0 - 0.5, 0.0);
	float base = floor(cell);
	return mix(getSample(base), getSample(base + 1.0), cell - base);
}

float getAmpWidth(float amplitude) {
	return (1.0-amplitude) * textureRes.x;
}

bool inWaveForm(vec2 pixel, float width) {
	float widthdiv2 = width/2.0;
	return pixel.x > widthdiv2 && pixel.x < textureRes.x-widthdiv2;
}

float getHightlight(float ampwidth) {
	float remapCoord = (ampwidth/textureRes.x)/2.0;
	float mappedCoord = map(openfl_TextureCoordv.x, remapCoord, 1.0-remapCoord, 0.0, 1.0);
	return 1.0-(abs(mappedCoord-0.5)*2.0);
}

void outlineWaveform(vec2 pixel, vec2 offset) {
	float amplitude = getAmplitude(pixel - offset);
	float ampwidth = (1.0-amplitude) * textureRes.x;

	if (!inWaveForm(pixel, ampwidth))
		gl_FragColor = vec4(vec3(0.), 1.);
}

void main()
{
	vec2 pixel = openfl_TextureCoordv * textureRes;
	float amplitude = getAmplitude(pixel);
	float ampwidth = getAmpWidth(amplitude);

	gl_FragColor = vec4(vec3(0.0), .1);

	vec2 uv = openfl_TextureCoordv.xy - 0.5;

	float c = BACKLIGHT;
	float a = abs(uv.x);
	float s = 1.0 - smoothstep(0.0, ampwidth/textureRes.x, a);
	c *= 1.33 - smoothstep(0.0, 0.5, a);
	c*=c*c;
	c += s*.5;

	if (inWaveForm(pixel, ampwidth))
		c += s;
	
	gl_FragColor = vec4((cos(6.283 * (uv.y + time + vec3(0.0,.33,0.66)))*map(getHightlight(amplitude), 0.0, 1.0, 0.5, 1.0)) + GLOW, 1.0) * c * BRIGHTNESS;
	gl_FragColor.xyz *= map(getHightlight(amplitude), 0.0, 1.0, 0.5, 1.0);
	gl_FragColor.xyz *= pixel.y+pixelOffset>playerPosition ? 0.6 : 1.0;
}