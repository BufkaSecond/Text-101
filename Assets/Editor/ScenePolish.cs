using System.IO;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.SceneManagement;

public static class ScenePolish
{
    public static void Setup()
    {
        var scene = EditorSceneManager.OpenScene("Assets/Scenes/SampleScene.unity", OpenSceneMode.Single);

        FixTextureImporters();
        FixMaterial();
        SetupSceneObjects();
        RenderPreview();

        AssetDatabase.SaveAssets();
        EditorSceneManager.MarkSceneDirty(scene);
        EditorSceneManager.SaveScene(scene);
        AssetDatabase.Refresh();
        Debug.Log("ScenePolish: setup complete");
    }

    static void FixTextureImporters()
    {
        SetTexture("Assets/Cube/Poliigon_MetalSteelBrushed_7174_BaseColor.jpg", isNormal: false, sRGB: true);
        SetTexture("Assets/Cube/Poliigon_MetalSteelBrushed_7174_Normal.png", isNormal: true, sRGB: false);
        SetTexture("Assets/Cube/Poliigon_MetalSteelBrushed_7174_Metallic.jpg", isNormal: false, sRGB: false);
        SetTexture("Assets/Cube/Poliigon_MetalSteelBrushed_7174_AmbientOcclusion.jpg", isNormal: false, sRGB: false);
        SetTexture("Assets/Cube/Poliigon_MetalSteelBrushed_7174_Roughness.jpg", isNormal: false, sRGB: false);
        SetTexture("Assets/Cube/Poliigon_MetalSteelBrushed_7174_Displacement.tiff", isNormal: false, sRGB: false);
    }

    static void SetTexture(string path, bool isNormal, bool sRGB)
    {
        var importer = AssetImporter.GetAtPath(path) as TextureImporter;
        if (importer == null)
        {
            Debug.LogWarning("ScenePolish: missing importer for " + path);
            return;
        }

        bool changed = false;
        if (isNormal)
        {
            if (importer.textureType != TextureImporterType.NormalMap) { importer.textureType = TextureImporterType.NormalMap; changed = true; }
        }
        else
        {
            if (importer.textureType != TextureImporterType.Default) { importer.textureType = TextureImporterType.Default; changed = true; }
            if (importer.sRGBTexture != sRGB) { importer.sRGBTexture = sRGB; changed = true; }
        }
        if (!importer.mipmapEnabled) { importer.mipmapEnabled = true; changed = true; }

        if (changed)
        {
            importer.SaveAndReimport();
            Debug.Log("ScenePolish: reimported " + path);
        }
    }

    static void FixMaterial()
    {
        var mat = AssetDatabase.LoadAssetAtPath<Material>("Assets/Cube/BrushedMetalMat.mat");
        if (mat == null)
        {
            Debug.LogWarning("ScenePolish: BrushedMetalMat not found");
            return;
        }

        var baseMap = AssetDatabase.LoadAssetAtPath<Texture>("Assets/Cube/Poliigon_MetalSteelBrushed_7174_BaseColor.jpg");
        var normalMap = AssetDatabase.LoadAssetAtPath<Texture>("Assets/Cube/Poliigon_MetalSteelBrushed_7174_Normal.png");
        var metallicMap = AssetDatabase.LoadAssetAtPath<Texture>("Assets/Cube/Poliigon_MetalSteelBrushed_7174_Metallic.jpg");
        var aoMap = AssetDatabase.LoadAssetAtPath<Texture>("Assets/Cube/Poliigon_MetalSteelBrushed_7174_AmbientOcclusion.jpg");

        mat.SetTexture("_BaseMap", baseMap);
        mat.SetTexture("_MainTex", baseMap);
        mat.SetTexture("_BumpMap", normalMap);
        mat.SetTexture("_MetallicGlossMap", metallicMap);
        mat.SetTexture("_OcclusionMap", aoMap);

        mat.SetTextureScale("_BaseMap", new Vector2(2f, 2f));
        mat.SetTextureScale("_BumpMap", new Vector2(2f, 2f));
        mat.SetTextureScale("_MetallicGlossMap", new Vector2(2f, 2f));
        mat.SetTextureScale("_OcclusionMap", new Vector2(2f, 2f));

        mat.SetFloat("_Metallic", 1.0f);
        mat.SetFloat("_Smoothness", 0.82f);
        mat.SetFloat("_BumpScale", 1.0f);
        mat.SetFloat("_OcclusionStrength", 1.0f);

        mat.EnableKeyword("_NORMALMAP");
        mat.EnableKeyword("_METALLICSPECGLOSSMAP");
        mat.EnableKeyword("_OCCLUSIONMAP");
        mat.DisableKeyword("_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A");
        mat.SetFloat("_SmoothnessTextureChannel", 0f);

        EditorUtility.SetDirty(mat);
        Debug.Log("ScenePolish: material updated");
    }

    static void SetupSceneObjects()
    {
        // Camera: pull back so the 5x5 cube fits nicely
        var cam = Camera.main;
        if (cam != null)
        {
            cam.orthographic = false;
            cam.fieldOfView = 45f;
            cam.transform.position = new Vector3(7f, 4.5f, -9f);
            cam.transform.rotation = Quaternion.Euler(21f, -38f, 0f);
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0.015f, 0.018f, 0.03f, 1f);
            cam.nearClipPlane = 0.1f;
            cam.farClipPlane = 200f;
        }

        // Cube
        var cube = GameObject.Find("Cube");
        if (cube != null)
        {
            cube.transform.position = Vector3.zero;
            cube.transform.rotation = Quaternion.Euler(-18f, 35f, 0f);
        }

        // Key spotlight
        var spotGO = GameObject.Find("Spot Light");
        if (spotGO == null)
        {
            spotGO = new GameObject("Spot Light");
            spotGO.AddComponent<Light>();
        }
        var spot = spotGO.GetComponent<Light>();
        spot.type = LightType.Spot;
        spot.color = new Color(1f, 0.96f, 0.9f, 1f);
        spot.intensity = 900f; // URP physical units (candela)
        spot.range = 30f;
        spot.spotAngle = 38f;
        spot.innerSpotAngle = 18f;
        spot.shadows = LightShadows.Soft;
        spot.shadowStrength = 1f;
        spot.transform.position = new Vector3(-7f, 9f, -7f);
        spot.transform.LookAt(cube != null ? cube.transform : null);

        // Cold rim/fill light from the opposite side
        var fillGO = GameObject.Find("Fill Light");
        if (fillGO == null)
        {
            fillGO = new GameObject("Fill Light");
            fillGO.AddComponent<Light>();
        }
        var fill = fillGO.GetComponent<Light>();
        fill.type = LightType.Point;
        fill.color = new Color(0.35f, 0.55f, 1f, 1f);
        fill.intensity = 350f;
        fill.range = 20f;
        fill.shadows = LightShadows.None;
        fill.transform.position = new Vector3(6f, 1.5f, 6f);

        // Quiet the 2D lighting
        var global2D = GameObject.Find("Global Light 2D");
        if (global2D != null)
            global2D.SetActive(false);

        RenderSettings.ambientMode = AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.02f, 0.025f, 0.04f, 1f);
        RenderSettings.ambientIntensity = 0.2f;
        RenderSettings.reflectionIntensity = 1.0f;

        var sky = AssetDatabase.GetBuiltinExtraResource<Material>("Default-Skybox.mat");
        if (sky != null)
            RenderSettings.skybox = sky;
    }

    static void RenderPreview()
    {
        var cam = Camera.main;
        if (cam == null) return;

        const int w = 1280, h = 720;
        var rt = new RenderTexture(w, h, 24, RenderTextureFormat.ARGB32);
        rt.antiAliasing = 4;
        var prev = RenderTexture.active;
        cam.targetTexture = rt;

        cam.Render();

        RenderTexture.active = rt;
        var tex = new Texture2D(w, h, TextureFormat.RGB24, false);
        tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
        tex.Apply();

        var outPath = Path.GetFullPath(Path.Combine(Application.dataPath, "..", "Library", "ScenePreview.png"));
        Directory.CreateDirectory(Path.GetDirectoryName(outPath));
        File.WriteAllBytes(outPath, tex.EncodeToPNG());
        Debug.Log("ScenePolish: preview written to " + outPath);

        cam.targetTexture = null;
        RenderTexture.active = prev;
        Object.DestroyImmediate(tex);
        Object.DestroyImmediate(rt);
    }
}
