# 测试语料

这里的文件是**真实 Unity 工程写出来的**，原样复制，只改了文件名（内容未改）。
写入侧的测试拿它们当基准：生成的文件要与它们逐字节一致，或者差异能逐条解释清楚。

来源工程：`CATSIM_2`，`m_EditorVersion: 2022.3.62f3c1`（Unity 2022.3.62）。

| 文件 | 原路径 | 用途 |
|---|---|---|
| `Unity2022/Folder/Art.meta` | `Assets/Art.meta` | 文件夹 `.meta` 的字段集与顺序（`DefaultImporter` + `folderAsset: yes`） |
| `Unity2022/Textures/hand.png.meta` | `Assets/Art/Build/Tex/2-1.png.meta` | Unity 2022.3 的 `TextureImporter`（`serializedVersion: 13`）：字段集、顺序、`platformSettings` 与 `spriteSheet` 的形状 |
| `Unity2022/Textures/EmojiOne.png.meta` | `Assets/TextMesh Pro/Sprites/EmojiOne.png.meta` | 另一代格式的 `TextureImporter`（`serializedVersion: 5`，多 Sprite 图集，含 `fileIDToRecycleName`）——用来验证"以样板为基础"能保留库不认识的字段 |
| `Unity2022/Materials/plane.mat` | `Assets/plane.mat` | URP Lit 材质：`Material` 的完整字段集与顺序（`serializedVersion: 8`） |
| `Unity2022/Materials/plane.mat.meta` | `Assets/plane.mat.meta` | `NativeFormatImporter` + `mainObjectFileID: 2100000` |
| `Unity2022/Materials/loading_Material.mat` | `Assets/ProjectMain/AppAssets/Generated/Fgui/loading_Material.mat` | 带**工程内贴图引用**的材质（`{fileID: 2800000, guid: ..., type: 3}`），也是 `m_SavedProperties` 各列表的排序样本 |
| `Unity2022/Prefabs/damGrp_8_s.prefab` | `Assets/Art/Build/Prefab/InputPSD/damGrp_8_s.prefab` | PSD 导出链生成的真实预制体：GameObject + Transform + MeshFilter + MeshRenderer + SortingGroup，与本库要生成的结构完全对应 |
| `Unity2022/Prefabs/damGrp_8_s.prefab.meta` | 同上 `.meta` | `PrefabImporter` |

## 为什么这些数字要来自语料

写入侧最容易犯的错是"凭记忆填字段"：少一个字段、字段顺序不对、`serializedVersion` 差一版，
Unity 都不会报错，而是**下次导入时把整个文件重写一遍**——在版本控制里表现为整文件 diff，
在编辑器里表现为"刚导出的资产被改动了"。所以这里的每个数值都从真实文件取样核对过，
测试断言也只认这些文件。
