#ifndef GAME_ENGINE_SHADER_COMPILER_H
#define GAME_ENGINE_SHADER_COMPILER_H

#include "CoreLib/Basic.h"
#include "HardwareRenderer.h"

namespace GameEngine
{
	struct DescriptorSetInfo
	{
		CoreLib::List<DescriptorLayout> Descriptors;
		int BindingPoint;
	};

    enum class ShaderVariableType
    {
        Data, Texture, StorageBuffer, UniformBuffer, Sampler
    };

    struct ShaderVariableLayout
    {
        CoreLib::String Name;
        int BindingOffset, BindingLength;
        int BindingSpace;
        ShaderVariableType Type;
    };

    struct ShaderTypeSymbol : public CoreLib::RefObject
    {
    public:
        CoreLib::String TypeName;
        CoreLib::String FileName;
        uint32_t TypeId;
        int UniformBufferSize = 0;
        CoreLib::EnumerableDictionary<CoreLib::String, ShaderVariableLayout> VarLayouts;
        bool HasMember(CoreLib::String memberName)
        {
            return VarLayouts.ContainsKey(memberName);
        }
    };

    struct ShaderEntryPoint : public CoreLib::RefObject 
    {
        CoreLib::String FileName;
        CoreLib::String FunctionName;
        StageFlags Stage;
        uint32_t Id;
    };

	class ShaderCompilationResult
	{
	public:
		CoreLib::List<CoreLib::List<char>> ShaderCode;
		CoreLib::String Diagnostics;
		CoreLib::EnumerableDictionary<CoreLib::String, DescriptorSetInfo> BindingLayouts;
    };

    class ShaderCompilationEnvironment : public CoreLib::RefObject
    {
    public:
        CoreLib::List<ShaderTypeSymbol*> SpecializationTypes;
    };

    class IShaderCompiler : public CoreLib::RefObject
    {
    public:
        virtual bool CompileShader(ShaderCompilationResult & src,
            const CoreLib::ArrayView<ShaderEntryPoint*> entryPoints,
            const ShaderCompilationEnvironment* env = nullptr) = 0;
        virtual ShaderTypeSymbol* LoadSystemTypeSymbol(CoreLib::String typeName) = 0;
        virtual ShaderTypeSymbol* LoadTypeSymbol(CoreLib::String fileName, CoreLib::String typeName) = 0;
        virtual ShaderEntryPoint* LoadShaderEntryPoint(CoreLib::String fileName, CoreLib::String functionName) = 0;
    };

    IShaderCompiler* CreateShaderCompiler();
    class ShaderSet
    {
    public:
        CoreLib::RefPtr<Shader> vertexShader, fragmentShader;
        operator bool()
        {
            return vertexShader && fragmentShader;
        }
    };
    ShaderSet CompileGraphicsShader(HardwareRenderer * hw, CoreLib::String fileName);
}

#endif