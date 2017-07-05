#define	PI			3.1415926
#define SGNBPPMAX	16	//maximum number of SGs on each pixel

// common constants
const	float	inverse_logAlpha_2 = 49.74958;//alpha = 0.99
const	float	log2_inverse_logAlpha_2 = 5.636612;//alpha = 0.99

const	float	mu_c = 1.17005;
const	float	lambda_c = 2.13326;
const	float	sqrt2 = 1.4142136;
const	float	sqrt2_2 = 0.70710678;
const   float   texCoordScale = 1.0;

uniform	vec4	spec;
uniform	mat4	lightMat;
uniform	vec3	viewPoint;
uniform	samplerCube		lightTex;
uniform sampler2DArray	texture;
uniform float	normalFactor;
uniform int		specCBFCount;
uniform float   prefilterLightLevelMax;

// diffuse parameters
uniform vec4	diff;
uniform int		diffCBFCount;
uniform vec3	diffCBFCenter[16];
uniform vec3	diffCBFColor[16];
uniform float	diffCBFLambda[16];
uniform int		ambtCBFCount;
uniform vec3	ambtCBFCenter[4];
uniform vec3	ambtCBFColor[4];
uniform float	ambtCBFLambda[4];

varying	vec3	position;
varying vec3	normal,	tangentPixel;
varying vec2	texCoordPixel;

void srbfTripleSRBF(out float lambda,	out vec3 pos,	out vec3 mu,
				   in float lambda1,	in vec3 pos1,	in vec3 mu1,
				   in float lambda2,	in vec3 pos2,	in vec3 mu2)
{
	float	lambda_m,	norm_pos_m;
	vec3	pos_m;
	lambda_m	= lambda1 + lambda2;
	pos_m	= (lambda1 * pos1 + lambda2 * pos2) / lambda_m;
	norm_pos_m	= length(pos_m);
	mu	= mu2 * mu1 * exp((norm_pos_m - 1.0) * lambda_m);
	lambda	= lambda_m * norm_pos_m;
	pos	= pos_m / norm_pos_m;
}
vec3 srbfDotSRBF(in vec3 pos1,	in float lambda1,	in vec3 mu1,
					in vec3 pos2,	in float lambda2,	in vec3 mu2)
{
	float d = length(lambda1 * pos1 + lambda2 * pos2);
	float l = lambda1 + lambda2;
	return  2.0 * PI * mu1 * mu2 / d * (exp(d - l) - exp(-d - l) );
}

vec3 global2Local(in vec3 posGlobal, in vec3 normal,	in vec3 tangent,	in vec3 bitangent)
{
	vec3 posLocal;
	posLocal.x = dot(posGlobal,tangent);
	posLocal.y = dot(posGlobal,bitangent);
	posLocal.z = dot(posGlobal,normal);
	return normalize(posLocal);
}
vec3 local2Global(in vec3 posLocal, in vec3 normal,	in vec3 tangent,	in vec3 bitangent)
{
	vec3 posGlobal;
	posGlobal = posLocal.x * tangent;
	posGlobal += posLocal.y * bitangent;
	posGlobal += posLocal.z * normal;
	return normalize(posGlobal);
}

void getTexture(out vec3 diffTex, out vec3 specTex,	out vec3 normalTex, 
				out float intensityTex[SGNBPPMAX], out vec3 centerTex[SGNBPPMAX], out float lambdaTex[SGNBPPMAX],
				out float interferenceD, out int interferenceN, out vec3 interferenceTangent, out vec3 interferenceIntensity)
{
	vec4 tmp = texture2DArray(texture, vec3(vec2(texCoordPixel.x, -texCoordPixel.y) * texCoordScale, 0));
	diffTex = tmp.rgb;
	normalTex.x = tmp.w;
	tmp = texture2DArray(texture,	vec3(vec2(texCoordPixel.x, -texCoordPixel.y)*texCoordScale, 1));
	specTex = tmp.rgb;
	normalTex.y = tmp.w;
	normalTex.z  = normalFactor;
	normalTex = normalize(normalTex);

	tmp = texture2DArray(texture, vec3(vec2(texCoordPixel.x, -texCoordPixel.y) * texCoordScale, 2));
	interferenceN = int(tmp.x);
	interferenceD = tmp.y;
	interferenceTangent.x = tmp.z;
	interferenceTangent.y = tmp.w;
	interferenceTangent.z = 0;
	tmp = texture2DArray(texture, vec3(vec2(texCoordPixel.x, -texCoordPixel.y) * texCoordScale, 3));
	interferenceIntensity = tmp.xyz;

	for (int j = 0; j < specCBFCount; j ++)
	{
		tmp = texture2DArray(texture, vec3(vec2(texCoordPixel.x, -texCoordPixel.y)*texCoordScale, j+4));
		intensityTex[j] = tmp.x;
		centerTex[j].z = sqrt(1-tmp.y*tmp.y-tmp.z*tmp.z);
		centerTex[j].x = tmp.y;
		centerTex[j].y = tmp.z;
		lambdaTex[j] = tmp.w;
	}
}

vec3 srbfDotLight(const in vec3 dirLight, const in vec3 mu, const in float lambda,	const in float log2_lambda)
{
	vec3	color;
	float	level = prefilterLightLevelMax-(log2_lambda + log2_inverse_logAlpha_2)*0.5;
	color	= textureCubeLod(lightTex,	dirLight,	level).xyz * mu / lambda;

	return	color;
}

vec3 blend3(vec3 x)
{
	 vec3 y = 1 - x * x;
	 y = max(y, vec3(0, 0, 0));
	 return y;
}

vec3 diffraction(in vec3 normal, in vec3 tangent,
				 in float d, in int nMax, in vec3 lightDir, in vec3 eyeDir)
{
	vec3 P = position;
	vec3 L = lightDir;
	vec3 V = eyeDir;
	vec3 H = L + V;
	vec3 N = normal;
	vec3 T = tangent;
	float u = dot(T, H) * d;
	float w = dot(N, H);
	if (u < 0)
		u = -u;
	vec3 cdiff = vec3(0, 0, 0);
	for (int n = 1; n <= nMax; n++)
	{
		float y = 2 * u / n - 1;
		cdiff.xyz += blend3(vec3(4 * (y - 0.75), 4 * (y - 0.5), 4 * (y - 0.25)));
	}
	return cdiff * max(0.f, dot(normal, lightDir));
}

void main()
{
	// get texture
	vec3 diffTex;
	vec3 specTex;
	vec3 normal_Local;
	vec3 centerTex[SGNBPPMAX];
	float lambdaTex[SGNBPPMAX];
	float intensityTex[SGNBPPMAX];
	float interferenceD;
	int interferenceN;
	vec3 interferenceT;
	vec3 interferenceS;

	getTexture(diffTex,	specTex, normal_Local, intensityTex, centerTex, lambdaTex, 
		interferenceD, interferenceN, interferenceT, interferenceS);

	normal	= normalize(normal);
	tangentPixel	= normalize(tangentPixel);
	vec3 bitangent	= normalize(cross(normal, tangentPixel) );

	// get view direction
	vec3 dir_o_Global = normalize(viewPoint - position);
	vec3 dir_o_Local  = global2Local(dir_o_Global, normal, tangentPixel, bitangent);

	vec3 color = 0.0;
	for (int j = 0; j < specCBFCount; j ++)
	{
		// get BRDF
		vec3  mu_D = intensityTex[j];
		float lambda_D = lambdaTex[j] * spec.w;
		vec3  pos_D = centerTex[j];
		// warp D to dir_i CBF
		vec3  pos_D_Warp = -reflect(dir_o_Local,	pos_D);
		float lambda_D_Warp	 = lambda_D / 4.0 / (abs(dot(dir_o_Local,normal_Local) ) + 0.3);
		// get FGC (microfacet model)
		float n = 1.5;
		float k = 0.5;
		float oDotn = max(0.0,dot(dir_o_Local,normal_Local));
		float G = oDotn/(oDotn+k*(1-oDotn));
		float c = max(0.0,dot(dir_o_Local,pos_D));
		float g = sqrt(n*n + c*c - 1);
		float F = 0.5*(g-c)*(g-c)/(g+c)/(g+c)*(1 + (c*(g+c)-1)/(c*(g-c)+1)*(c*(g+c)-1)/(c*(g-c)+1) );
		mu_D *= F *(G*G) / (4 * oDotn * oDotn + 0.1);
		// CBF triple cosine
		float lambda_BTC;
		vec3 pos_BTC;
		vec3 mu_BTC;
		srbfTripleSRBF(lambda_BTC,	pos_BTC,	mu_BTC,
					   lambda_D_Warp,	pos_D_Warp,	mu_D,
					   lambda_c,	normal_Local,	mu_c);
		// get global position
		vec3 pos_BTC_Global = local2Global(pos_BTC, normal, tangentPixel, bitangent);
		// CBF dot light
		color += srbfDotLight((lightMat * vec4(pos_BTC_Global,1.0) ).xyz, mu_BTC, lambda_BTC, log2(lambda_BTC) );
		//gl_FragColor.xyz = mu_D;
	}
	color *= specTex * spec.rgb;

	// compute diffuse color
		vec3  color_Diff = 0;
		// each light triple
		for (int i = 0; i < diffCBFCount; i ++)
		{
			vec3 diffCenter_Local = global2Local(diffCBFCenter[i], normal, tangentPixel, bitangent);
			color_Diff += diffCBFColor[i] * srbfDotSRBF(diffCenter_Local, diffCBFLambda[i], 1, normal_Local, lambda_c, mu_c);	
		}
		vec3  color_Ambt = 0;
		// each ambient light
		for (int i = 0; i < ambtCBFCount; i ++)
		{
			vec3 ambtCenter_Local = global2Local(ambtCBFCenter[i], normal, tangentPixel, bitangent);
			color_Ambt += ambtCBFColor[i] * srbfDotSRBF(ambtCenter_Local, ambtCBFLambda[i], 1, normal_Local, lambda_c, mu_c);
		}
		color_Diff += color_Ambt;
		color_Diff *= diffTex * diff.rgb;

	// diffraction color
	vec3 diffractionColor = 0;
		vec3 interferenceTangent = tangentPixel * interferenceT.x + bitangent * interferenceT.y;
		for (int i = 0; i < diffCBFCount; i ++)
			diffractionColor += interferenceS * diffCBFColor[i] * diffraction(normal, interferenceTangent,
				interferenceD, interferenceN, diffCBFCenter[i], dir_o_Global);
		diffractionColor *= diff.rgb;

	gl_FragColor.xyz = pow(diffractionColor + color + color_Diff, vec4(1.0/2.2));
}
