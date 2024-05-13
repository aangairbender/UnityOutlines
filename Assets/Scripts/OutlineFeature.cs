using System;
using UnityEngine.Rendering;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Outline
{
    public class OutlineFeature : ScriptableRendererFeature
    {
        public Settings[] OutlineSettings;
        private OutlinePass[] _outlinePasses;
        private StencilPass[] _stencilPasses;

        [Serializable]
        public class Settings
        {
            [Header("Visual")]
            [ColorUsage(true, true)]
            public Color Color = new Color(0.2f, 0.4f, 1, 1f);

            [Range(0.0f, 5.0f)]
            public float Width = 4f;

            [Header("Rendering")]
            public LayerMask LayerMask = -1;

            // TODO: Try this again when render layers are working with hybrid renderer.
            // [Range(0, 32)]
            // public int RenderLayer = 1;

            public RenderPassEvent RenderPassEvent = RenderPassEvent.AfterRenderingTransparents;

            public SortingCriteria SortingCriteria = SortingCriteria.CommonOpaque;
        }

        public override void Create()
        {
            _stencilPasses = new StencilPass[OutlineSettings.Length];
            _outlinePasses = new OutlinePass[OutlineSettings.Length];
            for (int i = 0; i < OutlineSettings.Length; i++)
            {
                Settings settings = OutlineSettings[i];
                _stencilPasses[i] = new StencilPass(settings);
                _outlinePasses[i] = new OutlinePass(settings);
            }
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            for (int i = 0; i < _outlinePasses.Length; i++)
            {
                renderer.EnqueuePass(_stencilPasses[i]);
                renderer.EnqueuePass(_outlinePasses[i]);
            }
        }
    }
}
