using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Outline
{
    public class StencilPass : ScriptableRenderPass
    {
        private const string ProfilerTag = "Stencil Pass";
        private const string ShaderName = "Hidden/Outline";

        private static readonly ShaderTagId _srpDefaultUnlit = new ShaderTagId("SRPDefaultUnlit");
        private static readonly ShaderTagId _universalForward = new ShaderTagId("UniversalForward");
        private static readonly ShaderTagId _lightweightForward = new ShaderTagId("LightweightForward");

        private static readonly List<ShaderTagId> _shaderTags = new List<ShaderTagId>
        {
            _srpDefaultUnlit, _universalForward, _lightweightForward,
        };

        private readonly OutlineFeature.Settings _settings;

        private readonly Material _stencilMaterial;
        private FilteringSettings _filteringSettings;

        public StencilPass(OutlineFeature.Settings settings)
        {
            profilingSampler = new ProfilingSampler(ProfilerTag);
            _settings = settings;
            renderPassEvent = settings.RenderPassEvent;

            // TODO: Try this again when render layers are working with hybrid renderer.
            // uint renderingLayerMask = 1u << settings.RenderLayer - 1;
            // _filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.LayerMask.value, renderingLayerMask);
            _filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.LayerMask.value);

            if (!_stencilMaterial)
            {
                _stencilMaterial = CoreUtils.CreateEngineMaterial(ShaderName);
            }
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            DrawingSettings drawingSettings = CreateDrawingSettings(
                _shaderTags,
                ref renderingData,
                _settings.SortingCriteria
            );
            drawingSettings.overrideMaterial = _stencilMaterial;
            drawingSettings.overrideMaterialPassIndex = 0;

            // TODO: Switch to this once mismatched markers bug is fixed.
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);
            // CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }
    }
}
