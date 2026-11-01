# Chinese display and search dictionaries

Unmodified text dictionaries from [BYVoid/OpenCC, ver.1.1.9](https://github.com/BYVoid/OpenCC/tree/ver.1.1.9/data/dictionary), licensed under Apache-2.0. Original license: `assets/licenses/opencc.txt`.

`STPhrases` and `STCharacters` resolve simplified forms; `TWVariants` and `HKVariants` select regional traditional characters. The three `TWPhrases` files provide Taiwanese UI terms. `lib/app_language.dart` performs bounded, cached longest-phrase conversion in Dart; it does not embed the OpenCC native engine. Reading text uses only offset-preserving replacements so bookmarks, selections and speech ranges retain their UTF-16 source coordinates. Source books and sync files are not rewritten.

`TSPhrases` and `TSCharacters` provide traditional-to-simplified normalization for search only. Queries keep the exact input first and add distinct simplified, standard traditional and regional character forms; each form has an independent remote cursor. Metadata matching uses the simplified key, not the app's display-language preference.
