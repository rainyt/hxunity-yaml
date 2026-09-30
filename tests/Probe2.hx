package;

import hxunity.yaml.Strings;
import hxunity.yaml.UnityDocumentSet;

/**
	Debug runner that isolates individual statements of the `documentSet` test.

	  HXU_CASE=1 neko build/probe.n
**/
class Probe2
{
	static function main()
	{
		var which = Sys.getEnv("HXU_CASE");
		if (which == null) which = "1";
		Sys.println("case " + which);
		switch (which)
		{
			case "1":
				var text = "%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero";
				Sys.println("detect=" + escape(Strings.detectLineEnding(text)));
			case "2":
				var crlf = "%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero".split("\n").join("\r\n");
				Sys.println("crlf length=" + crlf.length);
				var split = Strings.splitLines(crlf);
				Sys.println("splitLines=" + split.length);
				Sys.println("detect=" + escape(Strings.detectLineEnding(crlf)));
			case "3":
				var crlf = "%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero".split("\n").join("\r\n");
				var set = UnityDocumentSet.parse(crlf);
				Sys.println("documents=" + set.count() + " ending=" + escape(set.lineEnding));
			case "4":
				var crlf = "%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero".split("\n").join("\r\n");
				var set = UnityDocumentSet.parse(crlf);
				Sys.println("emitted length=" + set.emit().length + " equal=" + (set.emit() == crlf));
			case "5":
				var noTrailing = "%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero";
				var set2 = UnityDocumentSet.parse(noTrailing);
				Sys.println("noTrailing flag=" + set2.trailingNewline);
				Sys.println("equal=" + (set2.emit() == noTrailing));
			case "6":
				var meta = "fileFormatVersion: 2\nguid: fea157dfd84dee94f80991aca36dd03c\nPrefabImporter:\n  externalObjects: {}\n  userData: \n  assetBundleName: \n  assetBundleVariant: \n";
				var set = UnityDocumentSet.parse(meta);
				Sys.println("documents=" + set.count() + " header=" + set.at(0).hasHeader);
				Sys.println("emitted=[" + escape(set.emit()) + "]");
			case "7":
				var set = UnityDocumentSet.parse("%YAML 1.1\n--- !u!1 &1\nGameObject:\n  m_Name: hero");
				var id = set.newFileId();
				Sys.println("newFileId=" + haxe.Int64.toStr(id) + " contains=" + set.contains(id));
			default:
				Sys.println("unknown case");
		}
		Sys.println("done");
	}

	static function escape(text:String):String
	{
		return text.split("\r").join("\\r").split("\n").join("\\n");
	}
}
