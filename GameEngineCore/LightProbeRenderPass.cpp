#include "WorldRenderPass.h"
#include "Material.h"
#include "Mesh.h"
#include "CoreLib/LibIO.h"

using namespace CoreLib;
using namespace CoreLib::IO;

namespace GameEngine
{
	class LightProbeRenderPass : public WorldRenderPass
	{
	public:
		const char * GetShaderFileName() override
		{
			return "LightProbeForwardPass.slang";
		}
		RenderTargetLayout * CreateRenderTargetLayout() override
		{
			return hwRenderer->CreateRenderTargetLayout(MakeArray(
				AttachmentLayout(TextureUsage::ColorAttachment, StorageFormat::RGBA_F16),
				AttachmentLayout(TextureUsage::DepthAttachment, DepthBufferFormat)).GetArrayView(), false);
		}
		virtual void SetPipelineStates(FixedFunctionPipelineStates & state) override
		{
			state.blendMode = BlendMode::AlphaBlend;
			state.DepthCompareFunc = CompareFunc::LessEqual;
		}
		virtual const char * GetName() override
		{
			return "LightProbeForward";
		}
	};

	WorldRenderPass * CreateLightProbeRenderPass()
	{
		return new LightProbeRenderPass();
	}
}