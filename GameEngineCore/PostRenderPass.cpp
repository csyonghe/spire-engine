#include "PostRenderPass.h"
#include "HardwareRenderer.h"
#include "ShaderCompiler.h"
#include "CoreLib/LibIO.h"

using namespace CoreLib;
using namespace CoreLib::IO;

namespace GameEngine
{
	void PostRenderPass::Create(Renderer * renderer)
	{
		// Create deferred pipeline
		VertexFormat deferredVertexFormat;
		deferredVertexFormat.Attributes.Add(VertexAttributeDesc(DataType::Float2, 0, 0, 0));
		deferredVertexFormat.Attributes.Add(VertexAttributeDesc(DataType::Float2, 0, 2 * sizeof(float), 1));
		RefPtr<PipelineBuilder> pipelineBuilder = hwRenderer->CreatePipelineBuilder();
		pipelineBuilder->SetVertexLayout(deferredVertexFormat);
		ShaderCompilationResult rs;
		auto shaderFileName = GetShaderFileName();
        auto compiledShader = CompileGraphicsShader(rs, renderer->GetHardwareRenderer(), shaderFileName);
		if (!compiledShader)
			throw HardwareRendererException("Shader compilation failure");

        shaders.Add(compiledShader.vertexShader);
        shaders.Add(compiledShader.fragmentShader);

		pipelineBuilder->SetShaders(From(shaders).Select([](auto x) { return x.Ptr(); }).ToList().GetArrayView());
		pipelineBuilder->FixedFunctionStates.PrimitiveTopology = PrimitiveType::TriangleFans;
		descLayouts.SetSize(rs.BindingLayouts.Count());
		for (auto & desc : rs.BindingLayouts)
		{
			if (desc.BindingPoint == -1) continue;
			if (desc.BindingPoint >= descLayouts.Count())
				descLayouts.SetSize(desc.BindingPoint + 1);
			descLayouts[desc.BindingPoint] = hwRenderer->CreateDescriptorSetLayout(desc.Descriptors.GetArrayView());
		}
		pipelineBuilder->SetBindingLayout(From(descLayouts).Select([](auto x) { return x.Ptr(); }).ToList().GetArrayView());
		
		List<AttachmentLayout> renderTargets;
		SetupPipelineBindingLayout(pipelineBuilder.Ptr(), renderTargets);
		renderTargetLayout = hwRenderer->CreateRenderTargetLayout(renderTargets.GetArrayView());

		pipeline = pipelineBuilder->ToPipeline(renderTargetLayout.Ptr());
		
		commandBuffer = new AsyncCommandBuffer(hwRenderer);
		transferInCommandBuffer = new AsyncCommandBuffer(hwRenderer);
		transferOutCommandBuffer = new AsyncCommandBuffer(hwRenderer);
	}

	PostRenderPass::PostRenderPass(ViewResource * view)
	{
		viewRes = view;
		viewRes->Resized.Bind(this, &PostRenderPass::Resized);
	}

	PostRenderPass::~PostRenderPass()
	{
		viewRes->Resized.Unbind(this, &PostRenderPass::Resized);
	}

	void PostRenderPass::Execute(SharedModuleInstances sharedModules)
	{
		auto cmdBufIn = transferInCommandBuffer->BeginRecording();
		frameBuffer->GetRenderAttachments().GetTextures(textures);
		cmdBufIn->TransferLayout(textures.GetArrayView(), TextureLayoutTransfer::UndefinedToRenderAttachment);
		cmdBufIn->EndRecording();

		auto cmdBuf = commandBuffer->BeginRecording(frameBuffer.Ptr());
		if (clearFrameBuffer)
			cmdBuf->ClearAttachments(frameBuffer.Ptr());

		DescriptorSetBindings descBindings;
		UpdateDescriptorSetBinding(sharedModules, descBindings);

		cmdBuf->SetViewport(0, 0, viewRes->GetWidth(), viewRes->GetHeight());
		cmdBuf->BindPipeline(pipeline.Ptr());
		cmdBuf->BindVertexBuffer(sharedRes->fullScreenQuadVertBuffer.Ptr(), 0);
		for (auto & binding : descBindings.bindings)
			cmdBuf->BindDescriptorSet(binding.index, binding.descriptorSet);
		cmdBuf->Draw(0, 4);
		
		cmdBuf->EndRecording();

		auto cmdBufOut = transferOutCommandBuffer->BeginRecording();
		cmdBufOut->TransferLayout(textures.GetArrayView(), TextureLayoutTransfer::RenderAttachmentToSample);
		cmdBufOut->EndRecording();

		Array<CommandBuffer*, 3> buffers;
		//buffers.Add(cmdBufIn);
		buffers.Add(cmdBuf);
		//buffers.Add(cmdBufOut);
		hwRenderer->ExecuteNonRenderCommandBuffers(MakeArrayView(cmdBufIn));
		hwRenderer->ExecuteRenderPass(frameBuffer.Ptr(), buffers.GetArrayView(), nullptr);
		hwRenderer->ExecuteNonRenderCommandBuffers(MakeArrayView(cmdBufOut));

	}

	RefPtr<RenderTask> PostRenderPass::CreateInstance(SharedModuleInstances sharedModules)
	{
		RefPtr<PostPassRenderTask> rs = new PostPassRenderTask();
		rs->postPass = this;
		rs->sharedModules = sharedModules;
		return rs;
	}

	void PostRenderPass::SetSource(ArrayView<PostPassSource> sourceTextures)
	{
		sources.Clear();
		sources.AddRange(sourceTextures);
		AcquireRenderTargets();
	}

	void PostRenderPass::Resized()
	{
		RenderAttachments renderAttachments;
		UpdateRenderAttachments(renderAttachments);
		frameBuffer = renderTargetLayout->CreateFrameBuffer(renderAttachments);
	}
}

