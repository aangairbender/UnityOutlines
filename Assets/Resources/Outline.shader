// Original shader by @bgolus, modified slightly by @alexanderameye for URP, modified slightly more
// by @gravitonpunch for ECS/DOTS/HybridRenderer.
// https://twitter.com/bgolus
// https://medium.com/@bgolus/the-quest-for-very-wide-outlines-ba82ed442cd9
// https://alexanderameye.github.io/
// https://twitter.com/alexanderameye/status/1332286868222775298

Shader "Hidden/Outline"
{
    Properties 
    { 
        _MainTex ("Texture", 2D) = "white" {}
        // _Transparency ("Transparency", Float) = 1
    }

    SubShader
    {
        Tags {
            "RenderType" = "Opaque"
            "RenderPipeline" = "UniversalPipeline"
        }

        Cull Off
        ZWrite Off
        ZTest Always

        HLSLINCLUDE
        #define SNORM16_MAX_FLOAT_MINUS_EPSILON ((float)(32768-2) / (float)(32768-1))
        #define FLOOD_ENCODE_OFFSET float2(1.0, SNORM16_MAX_FLOAT_MINUS_EPSILON)
        #define FLOOD_ENCODE_SCALE float2(2.0, 1.0 + SNORM16_MAX_FLOAT_MINUS_EPSILON)

        #define FLOOD_NULL_POS -1.0
        #define FLOOD_NULL_POS_FLOAT2 float2(FLOOD_NULL_POS, FLOOD_NULL_POS)
        ENDHLSL

        Pass // 0
        {
            Name "STENCIL MASK"

            Stencil {
                Ref 1
                ReadMask 1
                WriteMask 1
                Comp NotEqual
                Pass Replace
            }

            ColorMask 0
            Blend Zero One
            
            HLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"        

            #pragma target 4.5

            struct appdata
            {
                float4 positionOS : POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : INSTANCEID_SEMANTIC;
                #endif
            };

            float4 vert (appdata i) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(i);
                return TransformObjectToHClip(i.positionOS.xyz);
            }

            void frag () {}
            ENDHLSL
        }

        Pass // 1
        {
            Name "BUFFERFILL"

            HLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"        

            #pragma target 4.5

            struct appdata
            {
                float4 positionOS : POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : INSTANCEID_SEMANTIC;
                #endif
            };

            float4 vert (appdata i) : SV_POSITION
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float4 pos = TransformObjectToHClip(i.positionOS.xyz);

                // flip the rendering "upside down" in non OpenGL to make things easier later
                // you'll notice none of the later passes need to pass UVs
                #ifdef UNITY_UV_STARTS_AT_TOP
                    // pos.y = -pos.y;
                #endif

                return pos;
            }

            half frag () : SV_TARGET
            {
                return 1.0;
            }
            ENDHLSL
        }

        Pass // 2
        {
            Name "JUMPFLOODINIT"

            HLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"        

            #pragma target 4.5

            struct appdata
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : INSTANCEID_SEMANTIC;
                #endif
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : CUSTOM_INSTANCE_ID;
                #endif
            };

            Texture2D _MainTex;

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_TexelSize;
            CBUFFER_END

            v2f vert (appdata i)
            {
                UNITY_SETUP_INSTANCE_ID(i);
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);

                return o;
            }

            float2 frag (v2f i) : SV_TARGET
            {
                // integer pixel position
                int2 uvInt = i.positionCS.xy;

                // sample silhouette texture for sobel
                half3x3 values;
                UNITY_UNROLL
                for(int u=0; u<3; u++)
                {
                    UNITY_UNROLL
                    for(int v=0; v<3; v++)
                    {
                        uint2 sampleUV = clamp(uvInt + int2(u-1, v-1), int2(0,0), (int2)_MainTex_TexelSize.zw - 1);
                        values[u][v] = _MainTex.Load(int3(sampleUV, 0)).r;
                    }
                }

                // calculate output position for this pixel
                float2 outPos = i.positionCS.xy * abs(_MainTex_TexelSize.xy) * FLOOD_ENCODE_SCALE - FLOOD_ENCODE_OFFSET;

                // interior, return position
                if (values._m11 > 0.99)
                return outPos;

                // exterior, return no position
                if (values._m11 < 0.01)
                return FLOOD_NULL_POS_FLOAT2;

                // sobel to estimate edge direction
                float2 dir = -float2(
                values[0][0] + values[0][1] * 2.0 + values[0][2] - values[2][0] - values[2][1] * 2.0 - values[2][2],
                values[0][0] + values[1][0] * 2.0 + values[2][0] - values[0][2] - values[1][2] * 2.0 - values[2][2]
                );

                // if dir length is small, this is either a sub pixel dot or line
                // no way to estimate sub pixel edge, so output position
                if (abs(dir.x) <= 0.005 && abs(dir.y) <= 0.005)
                return outPos;

                // normalize direction
                dir = normalize(dir);

                // sub pixel offset
                float2 offset = dir * (1.0 - values._m11);

                // output encoded offset position
                return (i.positionCS.xy + offset) * abs(_MainTex_TexelSize.xy) * FLOOD_ENCODE_SCALE - FLOOD_ENCODE_OFFSET;
            }
            ENDHLSL
        }

        Pass // 3
        {
            Name "JUMPFLOOD_SINGLEAXIS"

            HLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"        

            #pragma target 4.5

            struct appdata
            {
                float4 positionOS : POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : INSTANCEID_SEMANTIC;
                #endif
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : CUSTOM_INSTANCE_ID;
                #endif
            };

            Texture2D _MainTex;
            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_TexelSize;
            CBUFFER_END
            int2 _AxisWidth;

            v2f vert (appdata i)
            {
                UNITY_SETUP_INSTANCE_ID(i);
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);

                return o;
            }

            half2 frag (v2f i) : SV_TARGET {
                // integer pixel position
                int2 uvInt = int2(i.positionCS.xy);

                // initialize best distance at infinity
                float bestDist = 100000000;
                float2 bestCoord;

                // jump samples
                // only one loop
                UNITY_UNROLL
                for(int u=-1; u<=1; u++)
                {
                    // calculate offset sample position
                    int2 offsetUV = uvInt + _AxisWidth * u;

                    // .Load() acts funny when sampling outside of bounds, so don't
                    offsetUV = clamp(offsetUV, int2(0,0), (int2)_MainTex_TexelSize.zw - 1);

                    // decode position from buffer
                    float2 offsetPos = (_MainTex.Load(int3(offsetUV, 0)).rg + FLOOD_ENCODE_OFFSET) * _MainTex_TexelSize.zw / FLOOD_ENCODE_SCALE;

                    // the offset from current position
                    float2 disp = i.positionCS.xy - offsetPos;

                    // square distance
                    float dist = dot(disp, disp);

                    // if offset position isn't a null position or is closer than the best
                    // set as the new best and store the position
                    if (offsetPos.x != -1.0 && dist < bestDist)
                    {
                        bestDist = dist;
                        bestCoord = offsetPos;
                    }
                }

                // if not valid best distance output null position, otherwise output encoded position
                return isinf(bestDist) ? FLOOD_NULL_POS_FLOAT2 : bestCoord * _MainTex_TexelSize.xy * FLOOD_ENCODE_SCALE - FLOOD_ENCODE_OFFSET;
            }
            ENDHLSL
        }

        Pass // 4
        {
            Name "OUTLINE"

            
            Stencil {
                Ref 1
                ReadMask 1
                WriteMask 1
                Comp NotEqual
                Pass Zero
                Fail Zero
            }

            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"        

            #pragma target 4.5

            struct appdata
            {
                float4 positionOS : POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : INSTANCEID_SEMANTIC;
                #endif
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                #if UNITY_ANY_INSTANCING_ENABLED
                uint instanceID : CUSTOM_INSTANCE_ID;
                #endif
            };

            Texture2D _MainTex;


            half4 _OutlineColor;
            float _OutlineWidth;
            Texture2D _StencilMask;
            // CBUFFER_START(UnityPerMaterial)
            // float _Transparency;
            // CBUFFER_END

            v2f vert (appdata i)
            {
                UNITY_SETUP_INSTANCE_ID(i);
                v2f o;
                o.positionCS = TransformObjectToHClip(i.positionOS.xyz);

                return o;
            }

           half4 frag (v2f i) : SV_Target {

                // integer pixel position
                int2 uvInt = int2(i.positionCS.xy);

                // load encoded position
                float2 encodedPos = _MainTex.Load(int3(uvInt, 0)).rg;

                // early out if null position
                if (encodedPos.y == -1)
                    return half4(0,0,0,0);

                // decode closest position
                float2 nearestPos = (encodedPos + FLOOD_ENCODE_OFFSET) * abs(_ScreenParams.xy) / FLOOD_ENCODE_SCALE;

                // current pixel position
                float2 currentPos = i.positionCS.xy;

                // distance in pixels to closest position
                half dist = length(nearestPos - currentPos);

                // calculate outline
                // + 1.0 is because encoded nearest position is half a pixel inset
                // not + 0.5 because we want the anti-aliased edge to be aligned between pixels
                // distance is already in pixels, so this is already perfectly anti-aliased!
                half outline = saturate(_OutlineWidth - dist + 1.0);

                // apply outline to alpha
                half4 col = _OutlineColor;
                col.a *= outline;
                col.a *= 1.0 - _StencilMask.Load(int3(uvInt, 0)).r;
                //col.a *= _Transparency;

                // profit!
                return col;
            }
            ENDHLSL
        }
    }
}