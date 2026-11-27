// this causes issues apparently?? need to check GLSLSourceAssembler
// but it could just be unnecessary too anyway
// if not, put this also in editorWaveformsRainbow.frag
//#version 120

#pragma header

const vec3 gradient1 = vec3(114.0/255.0, 81.0/255.0, 135.0/255.0);
const vec3 gradient2 = vec3(144.0/255.0, 80.0/255.0, 186.0/255.0);

const vec4 outlineColor = vec4(0.1);
const vec3 lowDetailCol = vec3(0.0, 0.0, 1.0);

uniform vec2 textureRes;
uniform float pixelOffset;

uniform float playerPosition;

uniform sampler2D waveformTexture;
uniform vec2 waveformSize;

uniform bool lowDetail;

float catmullRom(
	float p0, float p1, float p2, float p3,
	float t
) {
	float t2 = t * t;
	float t3 = t2 * t;

	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0*p0 - 5.0*p1 + 4.0*p2 - p3) * t2 +
		(-p0 + 3.0*p1 - 3.0*p2 + p3) * t3
	);
}

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

// Cobertura del pixel dentro de la onda, con 1 unidad de antialias en los bordes.
float waveCoverage(vec2 pixel, float width) {
	float widthdiv2 = width/2.0;
	float distanceToEdge = min(pixel.x - widthdiv2, (textureRes.x - widthdiv2) - pixel.x);
	return clamp(distanceToEdge + 0.5, 0.0, 1.0);
}

float getHighlight(float ampWidth) {
	float remapCoord = (ampWidth/textureRes.x)/2.0;
	float mappedCoord = map(openfl_TextureCoordv.x, remapCoord, 1.0-remapCoord, 0.0, 1.0);
	return 1.0-(abs(mappedCoord-0.5)*2.0);
}

void outlineWaveform(vec2 pixel, vec2 offset) {
	float amplitude = getAmplitude(pixel - offset);
	float ampWidth = (1.0-amplitude) * textureRes.x;

	if (!inWaveForm(pixel, ampWidth))
		gl_FragColor -= outlineColor*mix(0.5, 0.8, amplitude);
}

void highDetailWaveform(vec2 pixel, float amplitude, float ampWidth, float coverage) {
	vec3 gradientColor = mix(gradient1, gradient2, openfl_TextureCoordv.x);
	gradientColor *= pixel.y+pixelOffset>playerPosition ? 0.7 : 1.0;
	gradientColor = mix(gradientColor, gradientColor * vec3(1.8), map(getHighlight(amplitude), 0.0, 1.0, 0.5, 1.0));

	float ampWidthHighlight = getAmpWidth(amplitude/3.0);
	if (inWaveForm(pixel, ampWidthHighlight))
		gradientColor = mix(gradientColor, gradientColor * vec3(1.8), map(getHighlight(ampWidthHighlight), 0.0, 1.0, 0.5, 1.0));

	float alpha = openfl_Alphav * coverage;
	gl_FragColor = vec4(vec3(gradientColor * mix(0.5, 0.8, amplitude)) * alpha, alpha);

	outlineWaveform(pixel, vec2(0.0, -1.0));
	outlineWaveform(pixel, vec2(0.0, 1.0));
}

void lowDetailWaveform(vec2 pixel, float amplitude, float ampWidth, float coverage) {
	float alpha = openfl_Alphav * coverage;
	gl_FragColor = vec4(lowDetailCol * (pixel.y+pixelOffset>playerPosition ? 0.7 : 1.0) * alpha, alpha);
}

void main()
{
	vec2 pixel = openfl_TextureCoordv * textureRes;
	float amplitude = getAmplitude(pixel);
	float ampWidth = getAmpWidth(amplitude);
	float coverage = waveCoverage(pixel, ampWidth);

	gl_FragColor = vec4(0.0);
	if (coverage <= 0.0) return;

	if (lowDetail) lowDetailWaveform(pixel, amplitude, ampWidth, coverage);
	else highDetailWaveform(pixel, amplitude, ampWidth, coverage);
}