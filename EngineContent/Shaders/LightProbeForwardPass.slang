import ShaderLib;

#ifdef IMPORT_MODULE_0
import IMPORT_MODULE_0;
#endif
#ifdef IMPORT_MODULE_1
import IMPORT_MODULE_1;
#endif
#ifdef IMPORT_MODULE_2
import IMPORT_MODULE_2;
#endif
#ifdef IMPORT_MODULE_3
import IMPORT_MODULE_3;
#endif
#ifdef IMPORT_MODULE_4
import IMPORT_MODULE_4;
#endif

#ifndef SPECIALIZATION_TYPE_0
#define SPECIALIZATION_TYPE_0 ViewParams 
#endif

#ifndef SPECIALIZATION_TYPE_1
#define SPECIALIZATION_TYPE_1 LightingEnvironment
#endif

#ifndef SPECIALIZATION_TYPE_2
import DefaultMaterial;
#define SPECIALIZATION_TYPE_2 DefaultMaterial
#endif

#ifndef SPECIALIZATION_TYPE_3
#define SPECIALIZATION_TYPE_3 StaticMeshTransform 
#endif

#ifndef SPECIALIZATION_TYPE_4
#define SPECIALIZATION_TYPE_4 StandardVertexAttribs<VertexUVSet1, StandardTangentFrame, VertexColorSet0, NoBoneWeightSet>
#endif

ParameterBlock<SPECIALIZATION_TYPE_0> gView;
ParameterBlock<SPECIALIZATION_TYPE_1> gLighting;
ParameterBlock<SPECIALIZATION_TYPE_2> gMaterial;
ParameterBlock<SPECIALIZATION_TYPE_3> gWorldTransform;

struct VSOutput
{
	float4 projPos : SV_POSITION;
    float4 worldPos_binormalSign : WORLDPOS;
    float3 normal : NORMAL;
    float3 tangent : TANGENT;
    SPECIALIZATION_TYPE_4.ColorSet vertColorSet;
    SPECIALIZATION_TYPE_4.UVSet vertUVSet;
    SPECIALIZATION_TYPE_4.BoneWeightSet.PackedType vertBoneWeightSet : BONEWEIGHTSET;
};

VSOutput vs_main(SPECIALIZATION_TYPE_4 vertexIn, uint vertexIndex : SV_VertexID)
{
	VSOutput rs;
    rs.vertColorSet = vertexIn.getColorSet();
    rs.vertUVSet = vertexIn.getUVSet();
    rs.vertBoneWeightSet = vertexIn.getBoneWeightSet().getPackedRepresentation();

    VertexAttribs<SPECIALIZATION_TYPE_4.UVSet, SPECIALIZATION_TYPE_4.ColorSet, SPECIALIZATION_TYPE_4.BoneWeightSet> vattribs;
    vattribs.uvSet = rs.vertUVSet;
    vattribs.colorSet = rs.vertColorSet;
    vattribs.boneWeightSet = vertexIn.getBoneWeightSet();

    VertexPositionInfo vin;
    vin.vertPos = vertexIn.getPos();
    vin.vertIndex = vertexIndex;
    vin.tangentFrame = vertexIn.getTangentFrame();
    VertexPositionInfo worldPos = gWorldTransform.getWorldSpacePos(vin, vattribs);
    rs.normal = worldPos.tangentFrame.vertNormal;
    rs.tangent = worldPos.tangentFrame.vertTangent;
    
    float3 displacement = gMaterial.getDisplacement(worldPos, vattribs, gView);
    rs.worldPos_binormalSign = float4(worldPos.vertPos + displacement, worldPos.tangentFrame.binormalSign);
    rs.projPos = PlatformNDC(mul(gView.viewProjectionTransform, float4(rs.worldPos_binormalSign.xyz, 1.0)));
    return rs;
}

float4 ps_main(VSOutput vsOut, float4 pixelLocation : SV_Position) : SV_Target
{
    VertexPositionInfo vin;
    vin.vertPos = vsOut.worldPos_binormalSign.xyz;
    vin.tangentFrame.vertNormal = normalize(vsOut.normal);
    vin.tangentFrame.vertTangent = normalize(vsOut.tangent);
    vin.tangentFrame.vertBinormal = cross(vin.tangentFrame.vertTangent, vin.tangentFrame.vertNormal);
    vin.tangentFrame.binormalSign = vsOut.worldPos_binormalSign.w;
    VertexAttribs<SPECIALIZATION_TYPE_4.UVSet, SPECIALIZATION_TYPE_4.ColorSet, SPECIALIZATION_TYPE_4.BoneWeightSet> vattribs;
    vattribs.uvSet = vsOut.vertUVSet;
    vattribs.colorSet = vsOut.vertColorSet;
    vattribs.boneWeightSet.setPackedRepresentation(vsOut.vertBoneWeightSet);
    SPECIALIZATION_TYPE_2.MaterialPattern pattern = gMaterial.evalPattern(vin, vattribs, gView);
    if (!pattern.alphaTest())
        discard;
    return pattern.computeForwardLighting<0>(gLighting, vin, gView, gWorldTransform.getLightmapId(), vattribs.uvSet.getUV(1),
        float4(pixelLocation.xy, vsOut.projPos.zw));
}