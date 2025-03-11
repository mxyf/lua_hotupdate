using UnityEngine;
using UnityEditor;
using System.IO;
using System.Text;
public class LuaFastProcessor : AssetPostprocessor
{
    protected const string HOT_FIX_STR = "HU.Update()";
    public static bool is_on = false;

    public static void OnPostprocessAllAssets(string[] importedAsset, string[] deletedAssets, string[] movedAssets, string[] movedFromAssetPaths)
    {
        if (!is_on){
            return;
        }

        if (Application.isPlaying)
        {
            var luaEnv = LEngine.Base.XLuaTool.Instance().GetLuaEnv();
            string path = Application.dataPath + "\\Path\\To\\hotupdatelist.lua";
            StringBuilder sb = new StringBuilder();
            sb.Append("local FileNameList = {\n");
            for (int i = 0; i < importedAsset.Length; i++)
            {
                bool isLuaFile = importedAsset[i].EndsWith(".lua");
                if (isLuaFile)
                {
                    if (luaEnv != null)
                    {
                        string strName = importedAsset[i].Replace(".lua", "");
                        string shortName = strName.Substring(strName.LastIndexOf("/") + 1);
                        if(shortName == "hotupdatelist" || shortName == "luahotupdate"){
                            continue;
                        }
                        string relativePath = strName.Replace("Assets/", "");
                        string absolutePath = Application.dataPath + '/' + relativePath;
                        sb.Append("\"");
                        sb.Append(absolutePath);
                        sb.Append("\",");                   
                    }
                }
            }

            sb.Append(@"
                    }
                    return FileNameList");
            File.WriteAllText(path,sb.ToString());
            if(luaEnv!=null)
                luaEnv.DoString(string.Format(HOT_FIX_STR));
        }
    }
}