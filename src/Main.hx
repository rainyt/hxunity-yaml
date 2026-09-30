package;

import hxunity.yaml.Scalars;
import hxunity.yaml.ScalarKind;
import hxunity.yaml.YamlMap;
import hxunity.yaml.YamlNode;
import hxunity.yaml.YamlScalar;
import hxunity.yaml.YamlSeq;
import hxunity.yaml.YamlParser;
import hxunity.yaml.YamlWriter;
import hxunity.yaml.UnityYamlDocument;
import hxunity.unity.FileId;
import haxe.Int64;

/** Temporary compile smoke test while the library is being built out. **/
class Main
{
	static function main()
	{
		var text = '%YAML 1.1\n%TAG !u! tag:unity3d.com,2011:\n--- !u!1 &338340333028156454\nGameObject:\n  m_Name: alex_fat\n  m_IsActive: 1\n';
		var docs = YamlParser.parseAll(text);
		Sys.println("docs=" + docs.length);
		for (d in docs)
		{
			Sys.println(d.toString());
			Sys.println(YamlWriter.write(d.body));
		}
		Sys.println("id=" + FileId.toStr(FileId.ofString("8601872862307532784")));
		Sys.println("quoted=" + Scalars.needsQuoting("-0.02"));
	}
}
