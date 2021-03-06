static const int MaxLightsPerTile = 128;

struct ViewParams
{
    float4x4 viewTransform;
    float4x4 viewProjectionTransform;
    float4x4 invViewTransform;
    float4x4 invViewProjTransform;
    float3 cameraPos;
    float time;  
    SamplerState textureSampler;  
};

float2 ProjCoordToUV(float2 coord)
{
#ifdef __D3D__
    return float2(coord.x, 1.0-coord.y);
#else
    return coord;
#endif
}
float2 UVToProjCoord(float2 coord)
{
#ifdef __D3D__
    return float2(coord.x, 1.0-coord.y);
#else
    return coord;
#endif
}

float4 QuaternionMul(float4 q1, float4 q2)
{
    float4 rs;
    rs.x = q1.w*q2.x + q1.x*q2.w + q1.y*q2.z - q1.z*q2.y;
    rs.y = q1.w*q2.y + q1.y*q2.w + q1.z*q2.x - q1.x*q2.z;
    rs.z = q1.w*q2.z + q1.z*q2.w + q1.x*q2.y - q1.y*q2.x;
    rs.w = q1.w*q2.w - q1.x*q2.x - q1.y*q2.y - q1.z*q2.z;
    return rs;
}

float4 QuaternionConjugate(float4 q)
{
    return float4(-q.x, -q.y, -q.z, q.w);    
}

float3 QuaternionRotate(float4 q, float3 v)
{
    float3 u = q.xyz;
    float s = q.w;
    return 2.0 * dot(u, v) * u + (s*s - dot(u, u)) * v + 2.0 * s * cross(u, v);
}

float ComputeLuminance(float3 color)
{
    return color.x * 0.3 + color.y * 0.59 + color.z * 0.11;
}

float3 desaturate(float3 color, float factor)
{
    float lum = ComputeLuminance(color);
    return lerp(color, float3(lum, lum, lum), factor);
}


struct TangentFrame
{
	float3 vertNormal;
    float3 vertTangent;
    float3 vertBinormal;
	float binormalSign;
    [mutating]
	void decode(uint frame)
	{
		float4 q;
		float inv255 = 2.0 / 255.0;
		q.x = float(frame & 255) * inv255 - 1.0;
		q.y = float((frame >> 8) & 255) * inv255 - 1.0;
		q.z = float((frame >> 16) & 255) * inv255 - 1.0;
		q.w = float((frame >> 24) & 255) * inv255 - 1.0;
		q = normalize(q);
		binormalSign = sign(q.w);
		vertNormal = QuaternionRotate(q, float3(0.0, 1.0, 0.0));
		vertTangent = QuaternionRotate(q, float3(1.0, 0.0, 0.0));
		vertBinormal = cross(vertTangent, vertNormal);
	}
	float3 WorldSpaceToTangentSpace(float3 v)
    {
        return float3(dot(v, vertTangent), dot(v, vertBinormal), dot(v, vertNormal));    
    }
    float3 TangentSpaceToWorldSpace(float3 v)
    {
        return v.x * vertTangent + v.y * vertBinormal * binormalSign + v.z * vertNormal;        
    }
};

struct VertexPositionInfo
{
	float3 vertPos;
    uint vertIndex;
    TangentFrame tangentFrame;
};

interface IWorldSpaceTransform
{
	VertexPositionInfo getWorldSpacePos<TVertAttribs : IVertexAttribs>(VertexPositionInfo input, TVertAttribs vertAttribs);
	uint getLightmapId();
};

struct StaticMeshTransform : IWorldSpaceTransform
{
	uint4 lightmapId;
	float4x4 worldMat;
  	VertexPositionInfo getWorldSpacePos<TVertAttribs : IVertexAttribs>(VertexPositionInfo input, TVertAttribs vertAttribs)
	{
		VertexPositionInfo rs;
		rs.vertPos = mul(worldMat, float4(input.vertPos, 1.0)).xyz;
        float3x3 worldRotMat = float3x3(worldMat);
		rs.tangentFrame.vertTangent = normalize(mul(worldRotMat, input.tangentFrame.vertTangent));
		rs.tangentFrame.vertBinormal = normalize(mul(worldRotMat, input.tangentFrame.vertBinormal));
		rs.tangentFrame.vertNormal = cross(rs.tangentFrame.vertBinormal, rs.tangentFrame.vertTangent);
        rs.tangentFrame.binormalSign = input.tangentFrame.binormalSign;
		return rs;
	}
	uint getLightmapId()
	{
		return lightmapId.x;
	}
};

#define MAX_BLEND_SHAPES 32

struct SkeletalAnimationTransform : IWorldSpaceTransform
{
    //uint4 lightmapId;
    float4x4 worldMat;
    float4 boneTransforms[90 * 2]; // dual quaternions
    uint4 blendShapeVertexStart[MAX_BLEND_SHAPES / 4];
    float4 blendShapeWeights[MAX_BLEND_SHAPES / 4];
    int blendShapeCount;
    StructuredBuffer<float4> blendshapeVertices;

    VertexPositionInfo getWorldSpacePos<TVertAttribs : IVertexAttribs>(VertexPositionInfo input, TVertAttribs vertAttribs)
    {
        VertexPositionInfo result;
        result.vertPos = float3(0.0);
        result.tangentFrame.vertBinormal = float3(0.0);
        result.tangentFrame.vertTangent = float3(0.0);
        float4 q = float4(0.0);
        float4 qe = float4(0.0);
        // Compute blend blend shapes
        TangentFrame originalTangentFrame = input.tangentFrame;
        float3 normalBlendShapeBias = 0;
        if (blendShapeCount)
        {
            [loop]
            for (int i = 0; i < blendShapeCount; i++)
            {
                uint vertStart = blendShapeVertexStart[i>>2][i&3];
                float weight = blendShapeWeights[i>>2][i&3];
                if (weight > 0.0f)
                {
                    float4 bsVert = blendshapeVertices[input.vertIndex + vertStart];
                    float3 bsPosition = bsVert.xyz;
                    input.vertPos += bsPosition * weight;
                    uint packedNormal = asuint(bsVert.w);
                    float inv1023 = 2.0 / 1023.0;
                    float3 newNormal = float3((packedNormal & 1023) * inv1023,
                                              ((packedNormal >> 10) & 1023) * inv1023,
                                              ((packedNormal >> 20) & 1023) * inv1023) - 1;
                    normalBlendShapeBias += newNormal * weight;
                }
            }
        }
        for (int i = 0; i < vertAttribs.getMaxBoneCount(); i++)
        {
            uint boneId = vertAttribs.getBoneId(i);
            if (boneId == 255) break;
            float boneWeight = vertAttribs.getBoneWeight(i);
             // Seek shortest rotation:
            float4 boneRotQ = boneTransforms[boneId * 2];
            if (dot(boneRotQ, q) < 0.f)
                boneWeight = -boneWeight;

            q += boneRotQ * boneWeight;
            qe += boneTransforms[boneId * 2 + 1] * boneWeight;
        }
        // normalize dual quaternion
        float norm = length(q);
        float invNorm = 1.0f / norm;
        q *= invNorm;
        qe *= invNorm;
        float3 v0 = q.xyz;
        float3 ve = qe.xyz;
        float3 trans = (ve*q.w - v0*qe.w + cross(v0, ve)) * 2.0f;
        result.vertPos = QuaternionRotate(q, input.vertPos) + trans;
        result.tangentFrame.vertBinormal = QuaternionRotate(q, input.tangentFrame.vertBinormal);
        result.tangentFrame.vertTangent = QuaternionRotate(q, input.tangentFrame.vertTangent);
        result.tangentFrame.binormalSign = input.tangentFrame.binormalSign;

        // apply world transform
        float3x3 worldRotMat = float3x3(worldMat);
        result.tangentFrame.vertBinormal = normalize(mul(worldRotMat, QuaternionRotate(q, input.tangentFrame.vertBinormal)));
        result.tangentFrame.vertTangent = normalize(mul(worldRotMat, QuaternionRotate(q, input.tangentFrame.vertTangent)));
        result.vertPos = mul(worldMat, float4(result.vertPos, 1.0)).xyz;
		result.tangentFrame.vertNormal = cross(result.tangentFrame.vertBinormal, result.tangentFrame.vertTangent);
        
        if (blendShapeCount)
        {
            float3 newNormal = normalize(mul(worldRotMat, QuaternionRotate(q, input.tangentFrame.vertNormal + normalBlendShapeBias)));
            if (dot(newNormal, result.tangentFrame.vertNormal) > 0.6)
            {
                result.tangentFrame.vertNormal = newNormal;
                result.tangentFrame.vertBinormal = normalize(cross(result.tangentFrame.vertTangent, result.tangentFrame.vertNormal));
                result.tangentFrame.vertTangent = cross(result.tangentFrame.vertNormal, result.tangentFrame.vertBinormal);
            }
        }
        
        return result;
    }
	uint getLightmapId()
	{
		return 0xFFFFFFFF;//lightmapId.x;
	}
};

interface IHeightField
{
	float GetHeight(float2 uvCoord);
};

struct TextureHeightField : IHeightField
{
    Texture2D texHeightField;
    SamplerState sampler;
    float GetHeight(float2 uv)
    {
        return texHeightField.Sample(sampler, uv).x;
    }
};

struct ParallaxOcclusionMappingOutput
{
    float2 uvOut;
    float heightOut;
    float parallaxScale;

    float selfShadow<THeightField : IHeightField>(THeightField heightfield, float3 L_tangentSpace)
    {
        float initialHeight = heightOut - 0.05;
        float3 L = L_tangentSpace;
        float2 initialTexCoord = uvOut;
        
        float shadowMultiplier = 1;
        float minLayers = 15;
        float maxLayers = 30;

        // calculate lighting only for surface oriented to the light source
        if (L.z > 0)
        {
            // calculate initial parameters
            float numSamplesUnderSurface = 0;
            shadowMultiplier = 0;
            float numLayers	= lerp(maxLayers, minLayers, abs(L.z));
            float layerHeight = max(0.03, abs(initialHeight / numLayers));
            float2 texStep = parallaxScale * L.xy / L.z / numLayers;
            texStep.y = -texStep.y;        
            // current parameters
            float currentLayerHeight = initialHeight - layerHeight;
            float2 currentTextureCoords = initialTexCoord + texStep;
            float heightFromTexture	= 1.0 - heightfield.GetHeight(currentTextureCoords); //heightTexture.Sample(textureSampler, currentTextureCoords).r;
            // while point is below depth 0.0 )
            int iterationLimit = 32;
            while(currentLayerHeight > 0 && iterationLimit > 0)
            {
                // if point is under the surface
                if(heightFromTexture < currentLayerHeight)
                {
                    numSamplesUnderSurface += 1;
                    break;
                }

                // ofFragmentet to the next layer
                currentLayerHeight -= layerHeight;
                currentTextureCoords += texStep;
                heightFromTexture = 1.0 - heightfield.GetHeight(currentTextureCoords); //-heightTexture.Sample(textureSampler, currentTextureCoords).r;
                iterationLimit--;
            }

            // Shadowing factor should be 1 if there were no points under the surface
            if(numSamplesUnderSurface < 1)
            {
                shadowMultiplier = 1;
            }
            else
            {
                shadowMultiplier = 0.0;
            }
        }
        return shadowMultiplier;
    }
};

ParallaxOcclusionMappingOutput ParallaxOcclusionMapping<THeightField : IHeightField>(THeightField heightfield, 
    float3 viewDirTangentSpace,
    float2 uv,
    float parallaxScale,
    SamplerState textureSampler)
{
	float3 V = viewDirTangentSpace;
    float2 T = uv;
        
    float parallaxHeight;
    // determine optimal number of layers
    float minLayers = 10;
    float maxLayers = 15;
    float numLayers = lerp(maxLayers, minLayers, abs(V.z));

    // height of each layer
    float layerHeight = 1.0 / numLayers;
    // current depth of the layer
    float curLayerHeight = 0.01;
    // shift of texture coordinates for each layer
    float2 dtex = parallaxScale * V.xy / max(V.z, 1e-5) / numLayers;
    dtex.y = -dtex.y;
    // current texture coordinates
    float2 currentTextureCoords = T;

    // depth from heightmap
    float heightFromTexture = 1.0 - heightfield.GetHeight(currentTextureCoords);//heightTexture.Sample(textureSampler, currentTextureCoords).r;

    int iterationLimit = 32;
    // while point is above the surface
    while (heightFromTexture > curLayerHeight && iterationLimit > 0) 
    {
        // to the next layer
        curLayerHeight += layerHeight; 
        // shift of texture coordinates
        currentTextureCoords -= dtex;
        // new depth from heightmap
        heightFromTexture = 1.0 - heightfield.GetHeight(currentTextureCoords);//-heightTexture.Sample(textureSampler, currentTextureCoords).r;
        iterationLimit--;
    }
        ///////////////////////////////////////////////////////////
    // Start of Relief Parallax Mapping

    // decrease shift and height of layer by half
    float2 deltaTexCoord = dtex / 2;
    float deltaHeight = layerHeight / 2;

    // return to the mid point of previous layer
    currentTextureCoords += deltaTexCoord;
    curLayerHeight -= deltaHeight;

    // binary search to increase precision of Steep Paralax Mapping
    int numSearches = 5;
    for (int i = 0; i <= numSearches; i++)
    {
        // decrease shift and height of layer by half
        deltaTexCoord /= 2;
        deltaHeight /= 2;

        // new depth from heightmap
        heightFromTexture = 1.0 - heightfield.GetHeight(currentTextureCoords);//heightTexture.Sample(textureSampler, currentTextureCoords).r;

        // shift along or agains vector V
        if(heightFromTexture > curLayerHeight) // below the surface
        {
            currentTextureCoords -= deltaTexCoord;
            curLayerHeight += deltaHeight;
        }
        else // above the surface
        {
            currentTextureCoords += deltaTexCoord;
            curLayerHeight -= deltaHeight;
        }
    }
    parallaxHeight = curLayerHeight; 
	
	ParallaxOcclusionMappingOutput rs;
    rs.parallaxScale = parallaxScale;
    rs.uvOut = currentTextureCoords;
	rs.heightOut = parallaxHeight;
	return rs;
}

float PhongApprox(float Roughness, float RoL)
{
    float a = Roughness * Roughness;	
    a = max(a, 0.008);					
    float a2 = a * a;						
    float rcp_a2 = 1.0/(a2);					
    float c = 0.72134752 * rcp_a2 + 0.39674113;	
    float p = rcp_a2 * exp2(c * RoL - c);	
    // Total 7 instr
    return min(p, rcp_a2);
}

float3 EnvBRDFApprox( float3 SpecularColor, float Roughness, float NoV )
{
    float4 c0 = float4(-1, -0.0275, -0.572, 0.022);
    float4 c1 = float4(1, 0.0425, 1.04, -0.04);
    float4 r = Roughness * c0 + c1;
    float a004 = min( r.x * r.x, exp2( -9.28 * NoV ) ) * r.x + r.y;
    float2 AB = float2( -1.04, 1.04 ) * a004 + r.zw;
    AB.y *= min(50.0 * SpecularColor.g, 1.0);
    return SpecularColor * AB.x + AB.y;
}

struct Light
{
    uint lightType_shadowMapId;
    float radius;
    float startAngle;
    float endAngle;
    float3 position;
    uint direction;
    float3 color;
    float padding;
    float4x4 lightMatrix;
    float4 padding2;
};

struct LightProbe
{
    float4 position_radius;
    float4 tintColor_envMapId;
};

float3 UnpackDir(uint dir)
{
    float alpha = (float(dir >> 16) / 65535.0) * 3.1415926 * 2.0f - 3.1415926;
    float beta = (float(dir & 65535) / 65535.0) * 3.1415926 - 3.1415926 * 0.5f;
    float3 rs;
    rs.x = cos(alpha) * cos(beta);
    rs.z = sin(alpha) * cos(beta);
    rs.y = sin(beta);
    return rs;
}

float Pow4(float x)
{
	return (x*x)*(x*x);
}

struct LightingEnvironment
{
    float4 zPlanes[2];
    float4x4 lightMatrix[8];
    float4 sunLightColor;
    float3 sunLightDir;
    int sunLightEnabled;
    int shadowMapId;
    int numCascades;
    int lightCount;
    int lightProbeCount;
    float4 ambient;
    int lightListTilesX, lightListTilesY, lightListSizePerTile;
    StructuredBuffer<Light> lights;
    StructuredBuffer<LightProbe> lightProbes;
    SamplerState envMapSampler;
    Texture2DArray shadowMapArray;
    SamplerComparisonState shadowMapSampler;
    TextureCubeArray envMap;
	Texture2DArray lightmapArrays[12];
    StructuredBuffer<uint> tiledLightList;
};

interface IMaterialPattern
{
	float4 computeForwardLighting<let useSpecularBRDF:int>(LightingEnvironment lightEnv,
		VertexPositionInfo shadingPoint,
		ViewParams viewParams,
		uint lightmapId,
		float2 lightmapUV,
        float4 pixelLocation);
    bool alphaTest();
	bool shadowAlphaTest();
    float4 getDiffuse();
    [mutating]
    void init();
};

interface ISelfShadow
{
	float get(float3 lightDir);
};

struct NoSelfShadow : ISelfShadow
{
	float get(float3 lightDir)
	{
		return 1.0;
	}
};

struct PomSelfShadow<THeightField : IHeightField> : ISelfShadow
{
    ParallaxOcclusionMappingOutput pom;
    THeightField heightField;
    TangentFrame tangentFrame;
    float get(float3 lightDir)
	{
		return pom.selfShadow(heightField, tangentFrame.WorldSpaceToTangentSpace(lightDir));
	}
};

struct PbrMaterialPattern<TSelfShadow : ISelfShadow> : IMaterialPattern
{
	float3 albedo;
    float3 normal;
    float roughness;
    float metallic;
    float specular;
    float opacity;
    float ao;
    float alphaTestThreshold;
	float shadowAlphaTestThreshold;
    bool isDoubleSided;
	TSelfShadow selfShadow;
    [mutating]
    void init()
    {
        albedo = float3(0.7,0.7,0.7);
        normal = float3(0.0, 0.0, 1.0);
        roughness = 1.0;
        metallic = 0.0;
        specular = 0.0;
        opacity = 1.0;
        ao = 1.0;
        isDoubleSided = false;
        alphaTestThreshold = 0.0;
		shadowAlphaTestThreshold = 0.0;
    }
    float4 getDiffuse()
    {
        return float4(albedo, opacity);
    }
    bool alphaTest()
    {
        return opacity > alphaTestThreshold;
    }
	bool shadowAlphaTest()
	{
		return opacity > shadowAlphaTestThreshold;
	}
	float4 computeForwardLighting<let useSpecularBRDF:int>(
		LightingEnvironment lightEnv,
		VertexPositionInfo shadingPoint,
		ViewParams viewParams,
		uint lightmapId,
		float2 lightmapUV,
        float4 pixelLocation)
	{
		float3 color = 0;
		float3 wnormal = shadingPoint.tangentFrame.TangentSpaceToWorldSpace(normal);
		float3 view = normalize(viewParams.cameraPos - shadingPoint.vertPos);
		float3 lNormal;
		if (isDoubleSided)
		{
			lNormal = dot(wnormal, view) < 0 ? -wnormal : wnormal;
		}
		else
		{
			lNormal = wnormal;
		}
		float3 R = reflect(-view, lNormal);
		float dielectricSpecluar = 0.02*specular;
		float3 diffuseColor = albedo - albedo * metallic;
		float3 specularColor = float3(dielectricSpecluar - dielectricSpecluar * metallic) + albedo * metallic;
		float3 viewPos = mul(viewParams.viewTransform, float4(shadingPoint.vertPos, 1.0)).xyz;

		if (lightmapId != 0xFFFFFFFF)
		{
			uint array = lightmapId >> 24;
			uint level = lightmapId & 0xFFFFFF;
			color = diffuseColor * lightEnv.lightmapArrays[array].Sample(viewParams.textureSampler, float3(lightmapUV, (float)level)).xyz;
		}
		else
            color = diffuseColor * lightEnv.ambient.xyz;

		if (lightEnv.sunLightEnabled != 0)
		{
			float shadow = selfShadow.get(lightEnv.sunLightDir);
            if (lightEnv.numCascades)
            {
#if 1
                bool terminated = false;
                #define CASCADE_LOOP_BODY(i) \
					if (!terminated && (-viewPos.z < lightEnv.zPlanes[i>>2][i&3])) \
					{ \
						float4 lightSpacePosT = mul(lightEnv.lightMatrix[i], float4(shadingPoint.vertPos, 1.0));\
						shadow = lightEnv.shadowMapArray.SampleCmp(lightEnv.shadowMapSampler,  \
						    float3(ProjCoordToUV(lightSpacePosT.xy / lightSpacePosT.w), i+lightEnv.shadowMapId), lightSpacePosT.z / lightSpacePosT.w);\
                        terminated = true;\
					} \
                    terminated = terminated || i >= lightEnv.numCascades; 
                CASCADE_LOOP_BODY(0)
                CASCADE_LOOP_BODY(1)
                CASCADE_LOOP_BODY(2)
                CASCADE_LOOP_BODY(3)
                CASCADE_LOOP_BODY(4)
                CASCADE_LOOP_BODY(5)
                CASCADE_LOOP_BODY(6)
                CASCADE_LOOP_BODY(7)
#else
                [loop]
                for (int i = 0; i < lightEnv.numCascades; i++)
                {
                    if (-viewPos.z < lightEnv.zPlanes[i >> 2][i & 3])
                    {
                        float4 lightSpacePosT = mul(lightEnv.lightMatrix[i], float4(shadingPoint.vertPos, 1.0));
                        shadow *= lightEnv.shadowMapArray.SampleCmp(lightEnv.shadowMapSampler,
                            float3(ProjCoordToUV(lightSpacePosT.xy / lightSpacePosT.w), i + lightEnv.shadowMapId), lightSpacePosT.z / lightSpacePosT.w);
                        break;
                    }
                }
#endif
            }
			float NoV = max(dot(lNormal, view), 0.0);
			float3 fspecularColor = specularColor;//EnvBRDFApprox(specularColor, roughness, NoV);
			float3 R = reflect(-view, lNormal);
			float RoL = max(0, dot(R, lightEnv.sunLightDir));
			float dotNL = clamp(dot(lNormal, lightEnv.sunLightDir), 0.01, 0.99);
            float3 lightingColor = diffuseColor;
            if (useSpecularBRDF)
                lightingColor += fspecularColor * PhongApprox(roughness, RoL);
            lightingColor *= shadow;
			color += lightEnv.sunLightColor.xyz * dotNL * lightingColor;
		}

        int tileX = int(pixelLocation.x / 16);
        int tileY = int(pixelLocation.y / 16);
        int lightListOffset = (tileY * lightEnv.lightListTilesX + tileX) * MaxLightsPerTile;
        int lightCount = 0;
        [loop]
		for (int i = 0; i < MaxLightsPerTile; i++)
		{
            uint bufferContent = lightEnv.tiledLightList[lightListOffset + i];
            uint lightId = bufferContent & 0xFFFF;
            if (lightId == 0xFFFF)
                break;
            lightCount++;
			Light light = lightEnv.lights[lightId];
			float3 path = light.position - shadingPoint.vertPos;
            float distSquared = dot(path, path);
            if (light.radius == 0.0f || distSquared < light.radius * light.radius)
            {
                uint lightType = light.lightType_shadowMapId & 65535;
                uint shadowMapId = light.lightType_shadowMapId >> 16;
                float3 lightDir = float3(0.0);
                float actualDecay = 1.0;
                if (light.radius > 0.0f)
                    actualDecay = lerp(1.0, 0.0, sqrt(sqrt(distSquared / (light.radius * light.radius))));
                if (lightType == 0 || lightType == 2) //point light
                {
                    lightDir = normalize(path);
                    if (lightType == 2)
                    {
                        float ang = acos(dot(lightDir, UnpackDir(light.direction)));
                        actualDecay *= lerp(1.0, 0.0, clamp((ang - light.startAngle) / (light.endAngle - light.startAngle), 0.0, 1.0));
                    }
                }
                else if (lightType == 1) // directional light
                {
                    lightDir = UnpackDir(light.direction);
                }
                float shadow = selfShadow.get(lightDir);
                if (shadowMapId != 65535)
                {
                    float4 lightSpacePosT = mul(light.lightMatrix, float4(shadingPoint.vertPos, 1.0));
                    if (lightSpacePosT.w > 1e-4f)
                    {
                        float3 lightSpacePos = lightSpacePosT.xyz / lightSpacePosT.w;
                        float val = lightEnv.shadowMapArray.SampleCmp(lightEnv.shadowMapSampler,
                            float3(ProjCoordToUV(lightSpacePos.xy), shadowMapId), lightSpacePos.z);
                        shadow *= val;
                    }
                    else
                        shadow = 0.0f;
                }

                float dotNL = clamp(dot(lNormal, lightDir), 0.0, 1.0);

                float3 lightingColor = diffuseColor * dotNL;
                if (useSpecularBRDF)
                {
                    float RoL = max(0, dot(R, lightDir));
                    float NoV = max(dot(lNormal, view), 0.0);
                    float3 fspecularColor = EnvBRDFApprox(specularColor, roughness, NoV);
                    lightingColor += fspecularColor * PhongApprox(roughness, RoL);
                }
                lightingColor *= (shadow * actualDecay);
                color += light.color * lightingColor;
            }
		}

        if (useSpecularBRDF)
        {
            // weighted sum over light probes
            float3 specularIBL = 0.0;
            float3 diffuseIBL = 0.0;
            float specularWeights = 0.0;
            float diffuseWeights = 0.0;
            [loop]
            for (int i = 0; i < MaxLightsPerTile; i++)
            {
                uint bufferContent = lightEnv.tiledLightList[lightListOffset + i];
                uint lightProbeIndex = bufferContent >> 16;
                if (lightProbeIndex == 0xFFFF)
                    break;
                LightProbe lp = lightEnv.lightProbes[lightProbeIndex];
                float dist = length(shadingPoint.vertPos - lp.position_radius.xyz);
                float radius = lp.position_radius.w;
                if (radius == 0.0) radius = 1e7f;
                float weight = 10000.0 / (dist*dist);
                weight = lerp(weight, 0.0, max((dist - radius * 0.5) / (radius*0.5), 0.0));
                if (dist < radius)
                {
                    int envMapId = asint(lp.tintColor_envMapId.w);
                    float3 lpTint = lp.tintColor_envMapId.xyz;
                    if (envMapId != -1)
                    {
                        specularIBL += lightEnv.envMap.SampleLevel(lightEnv.envMapSampler, float4(R, float(envMapId)),
                            clamp(roughness, 0.0, 1.0) * 6.0).xyz * lpTint * weight;
                        specularWeights += weight;
                        if (lightmapId == 0xFFFFFFFF)
                        {
                            diffuseIBL += (lightEnv.envMap.SampleLevel(lightEnv.envMapSampler, float4(lNormal, float(envMapId)),
                                6.0).xyz) * lpTint * weight;
                            diffuseWeights += weight;
                        }
                    }
                }
            }
            if (specularWeights > 0.0)
            {
                specularWeights = 1.0 / specularWeights;
                color += specularIBL * specularColor * specularWeights;
            }
            if (diffuseWeights > 0.0)
            {
                diffuseWeights = 1.0 / diffuseWeights;
                color += diffuseIBL * diffuseColor * diffuseWeights;
            }
        }
        color *= ao;
        return clamp(float4(color, opacity), float4(0.0), float4(100.0f));
    }
};

interface IMaterial
{
	associatedtype MaterialPattern : IMaterialPattern;
	MaterialPattern evalPattern<TVertAttribs : IVertexAttribs>(VertexPositionInfo shadingPoint, TVertAttribs vertAttribs, ViewParams viewParams);
	float3 getDisplacement<TVertAttribs : IVertexAttribs>(VertexPositionInfo shadingPoint, TVertAttribs vertAttribs, ViewParams viewParams);
}

interface IVertexColorSet
{
	float4 getColor(int index);
};

interface IVertexUVSet
{
	float2 getUV(int index);
};

interface IVertexAttribs
{
	float4 getColor(int index);
	float2 getUV(int index);
	uint getBoneId(int index);
	float getBoneWeight(int index);
	int getMaxBoneCount();
}

struct VertexAttribs<TVertexUVSet : IVertexUVSet, TColorSet : IVertexColorSet, TBoneWeightSet : IBoneWeightSet> : IVertexAttribs
{
	TVertexUVSet uvSet;
	TColorSet colorSet;
	TBoneWeightSet boneWeightSet;
	float4 getColor(int index) {return colorSet.getColor(index);}
	float2 getUV(int index) { return uvSet.getUV(index); }
	uint getBoneId(int index)
	{
		return boneWeightSet.getBoneId(index);
	}
	float getBoneWeight(int index)
	{
		return boneWeightSet.getBoneWeight(index);
	}
	int getMaxBoneCount()
	{
		return boneWeightSet.getMaxBoneCount();
	}
};

struct VertexColorSet0 : IVertexColorSet
{
	float4 getColor(int index) { return 0.0; }
};

struct VertexColorSet1 : IVertexColorSet
{
    float4 value : COLOR0;
	float4 getColor(int index) { return value; }
};

struct VertexColorSet2 : IVertexColorSet
{
    float4 value0 : COLOR0;
    float4 value1 : COLOR1;

	float4 getColor(int index)
	{
		switch (index)
		{
		case 0:
			return value0;
		case 1:
			return value1;
		default:
			return 0.0;
		}
	}
};

struct VertexColorSet3 : IVertexColorSet
{
    float4 value0 : COLOR0;
    float4 value1 : COLOR1;
	float4 value2 : COLOR2;
	float4 getColor(int index)
	{
		switch (index)
		{
		case 0:
			return value0;
		case 1:
			return value1;
		case 2:
			return value2;
		default:
			return 0.0;
		}
	}
};

struct VertexColorSet4 : IVertexColorSet
{
    float4 value0 : COLOR0;
    float4 value1 : COLOR1;
	float4 value2 : COLOR2;
	float4 value3 : COLOR3;

	float4 getColor(int index)
	{
		switch (index)
		{
		case 0:
			return value0;
		case 1:
			return value1;
		case 2:
			return value2;
		case 3:
			return value3;
		default:
			return 0.0;
		}
	}
};

struct VertexUVSet0 : IVertexUVSet
{
	float2 getUV(int index) { return float2(0.0); }
};

struct VertexUVSet1 : IVertexUVSet
{
	float2 value : TEXCOORD0;
	float2 getUV(int index) { return value; }
};

struct VertexUVSet2 : IVertexUVSet
{
	float2 value0: TEXCOORD0;
	float2 value1: TEXCOORD1;
	float2 getUV(int index)
	{
		switch (index)
		{
		case 0:
			return value0;
		case 1:
			return value1;
		default:
			return float2(0.0);
		}
	}
};

interface IBoneWeightSet
{
	associatedtype PackedType;
	PackedType getPackedRepresentation();
	[mutating]
	void setPackedRepresentation(PackedType val);
	float getBoneWeight(int index);
	uint getBoneId(int index);
	int getMaxBoneCount();
}

struct NoBoneWeightSet : IBoneWeightSet
{
	struct PackedType {};
	PackedType getPackedRepresentation() { PackedType rs; return rs; }
	[mutating]
	void setPackedRepresentation(PackedType val) {}
	float getBoneWeight(int index) {return 0.0;}
	uint getBoneId(int index) {return 255;}
	int getMaxBoneCount() {return 0;}
};

struct StandardBoneWeightSet : IBoneWeightSet
{
	struct PackedType
	{
		uint boneIds : BONEIDS;
		uint boneWeights : BONEWEIGHTS;
	};
	PackedType value;
	PackedType getPackedRepresentation() { return value; }
    [mutating]
	void setPackedRepresentation(PackedType val) { value = val; }
	uint getBoneId(int i)
	{
		return (value.boneIds >> (i*8)) & 255;
	}
	float getBoneWeight(int index)
	{
		return ((float)((value.boneWeights >> (index*8)) & 255)) * (1.0/255.0);
	}
	int getMaxBoneCount() {return 4;}
};


interface IVertexFormat
{
	float3 getPos();
	TangentFrame getTangentFrame();
	associatedtype ColorSet : IVertexColorSet;
	associatedtype UVSet : IVertexUVSet;
	associatedtype BoneWeightSet : IBoneWeightSet;
	ColorSet getColorSet();
	UVSet getUVSet();
	BoneWeightSet getBoneWeightSet();
};

interface ITangentFrame
{
	TangentFrame get();
};

struct NoTangentFrame : ITangentFrame
{
	TangentFrame get()
	{
		TangentFrame t;
		t.vertNormal = float3(0.0, 1.0, 0.0);
		t.vertTangent = float3(1.0, 0.0, 0.0);
		t.vertBinormal = float3(0.0, 0.0, 1.0);
		t.binormalSign = 1.0;
		return t;
	}
};

struct StandardTangentFrame : ITangentFrame
{
	uint packedQuaternion : TANGENT;
	TangentFrame get()
	{
		TangentFrame rs;
		rs.decode(packedQuaternion);
		return rs;
	}
};

struct StandardVertexFormat<TUVSet : IVertexUVSet, TTangentFrame : ITangentFrame, TColorSet : IVertexColorSet, TBoneWeightSet : IBoneWeightSet> : IVertexFormat
{
	typedef TUVSet UVSet;
	typedef TColorSet ColorSet;
	typedef TBoneWeightSet BoneWeightSet;
	float3 vertPos:POSITION;
	TUVSet uvSet;
	TTangentFrame vertTangentFrame;
	TColorSet colorSet;
	TBoneWeightSet.PackedType boneWeightSet;
	float3 getPos() { return vertPos; }
	TangentFrame getTangentFrame()
	{
		return vertTangentFrame.get();
	}
	ColorSet getColorSet()
	{
		return colorSet;
	}
	UVSet getUVSet()
	{
		return uvSet;
	}
	BoneWeightSet getBoneWeightSet()
	{
        TBoneWeightSet rs;
        rs.setPackedRepresentation(boneWeightSet);
		return rs;
	}
};

struct LightmapGBufferGlobalParams
{
    RWStructuredBuffer<float3> vertices;
};

[__AttributeUsage(_AttributeTargets.Struct)]
struct TransparentAttribute
{
};
[__AttributeUsage(_AttributeTargets.Struct)]
struct DoubleSidedAttribute
{
};

float4 PlatformNDC(float4 projCoord)
{
    return projCoord;
}