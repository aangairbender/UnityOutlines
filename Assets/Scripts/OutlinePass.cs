using System;
using System.Collections.Generic;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Outline
{
    public class OutlinePass : ScriptableRenderPass
    {
        private const string ProfilerTag = "Outline Pass";
        private const string ShaderName = "Hidden/Outline";

        private static readonly ShaderTagId _srpDefaultUnlit = new ShaderTagId("SRPDefaultUnlit");
        private static readonly ShaderTagId _universalForward = new ShaderTagId("UniversalForward");
        private static readonly ShaderTagId _lightweightForward = new ShaderTagId("LightweightForward");

        private static readonly List<ShaderTagId> _shaderTags = new List<ShaderTagId>
        {
            _srpDefaultUnlit, _universalForward, _lightweightForward,
        };

        private static readonly int _silhouetteBufferID = Shader.PropertyToID("_SilhouetteBuffer");
        private static readonly int _nearestPointID = Shader.PropertyToID("_NearestPoint");
        private static readonly int _nearestPointPingPongID = Shader.PropertyToID("_NearestPointPingPong");
        private static readonly int _axisWidthID = Shader.PropertyToID("_AxisWidth");
        private static readonly int _stencilMask = Shader.PropertyToID("_StencilMask");
        private static readonly int _outlineColorID = Shader.PropertyToID("_OutlineColor");
        private static readonly int _outlineWidthID = Shader.PropertyToID("_OutlineWidth");
        private readonly Material _bufferFillMaterial;
        private readonly Material _outlineMaterial;
        private readonly OutlineFeature.Settings _settings;
        private RenderTargetIdentifier _cameraColor;
        private FilteringSettings _filteringSettings;

        public OutlinePass(OutlineFeature.Settings settings)
        {
            profilingSampler = new ProfilingSampler(ProfilerTag);
            _settings = settings;
            renderPassEvent = settings.RenderPassEvent;

            // TODO: Try this again when render layers are working with hybrid renderer.
            // uint renderingLayerMask = 1u << settings.RenderLayer - 1;
            // _filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.LayerMask.value, renderingLayerMask);
            _filteringSettings = new FilteringSettings(RenderQueueRange.all, settings.LayerMask.value);

            if (!_outlineMaterial)
            {
                _outlineMaterial = CoreUtils.CreateEngineMaterial(ShaderName);
            }
            _outlineMaterial.SetColor(_outlineColorID, settings.Color);
            _outlineMaterial.SetFloat(_outlineWidthID, Mathf.Max(1f, settings.Width));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            RenderTextureDescriptor descriptor = renderingData.cameraData.cameraTargetDescriptor;

            descriptor.graphicsFormat = GraphicsFormat.R8_UNorm;
            descriptor.msaaSamples = Mathf.Max(1, QualitySettings.antiAliasing);
            descriptor.depthBufferBits = 0;
            descriptor.sRGB = false;
            descriptor.useMipMap = false;
            descriptor.autoGenerateMips = false;
            cmd.GetTemporaryRT(_silhouetteBufferID, descriptor, FilterMode.Point);

            descriptor.graphicsFormat = GraphicsFormat.R16G16_SNorm;
            descriptor.msaaSamples = 1;
            cmd.GetTemporaryRT(_nearestPointID, descriptor, FilterMode.Point);
            cmd.GetTemporaryRT(_nearestPointPingPongID, descriptor, FilterMode.Point);

            ConfigureTarget(_silhouetteBufferID);
            ConfigureClear(ClearFlag.Color, Color.clear);

            _cameraColor = renderingData.cameraData.renderer.cameraColorTarget;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            DrawingSettings drawingSettings = CreateDrawingSettings(
                _shaderTags,
                ref renderingData,
                _settings.SortingCriteria
            );
            drawingSettings.overrideMaterial = _outlineMaterial;
            drawingSettings.overrideMaterialPassIndex = 1;

            int numMips = Mathf.CeilToInt(Mathf.Log(_settings.Width + 1.0f, 2f));
            int jfaIterations = numMips - 1;

            // TODO: Switch to this once mismatched markers bug is fixed.
            CommandBuffer cmd = CommandBufferPool.Get(ProfilerTag);
            // CommandBuffer cmd = CommandBufferPool.Get();
            using (new ProfilingScope(cmd, profilingSampler))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref _filteringSettings);

                //Blit(cmd, _silhouetteBufferID, _cameraColor, _outlineMaterial, 5);

                Blit(cmd, _silhouetteBufferID, _nearestPointID, _outlineMaterial, 2);

                for (int i = jfaIterations; i >= 0; i--)
                {
                    float stepWidth = Mathf.Pow(2, i) + 0.5f;

                    cmd.SetGlobalVector(_axisWidthID, new Vector2(stepWidth, 0f));
                    Blit(cmd, _nearestPointID, _nearestPointPingPongID, _outlineMaterial, 3);
                    cmd.SetGlobalVector(_axisWidthID, new Vector2(0f, stepWidth));

                    Blit(cmd, _nearestPointPingPongID, _nearestPointID, _outlineMaterial, 3);
                }


                cmd.SetGlobalTexture(_stencilMask, _silhouetteBufferID);
                cmd.Blit(_nearestPointID, _cameraColor, _outlineMaterial, 4);
            }

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            if (cmd == null)
            {
                throw new ArgumentNullException("cmd");
            }

            cmd.ReleaseTemporaryRT(_silhouetteBufferID);
            cmd.ReleaseTemporaryRT(_nearestPointID);
            cmd.ReleaseTemporaryRT(_nearestPointPingPongID);
        }
    }
}
