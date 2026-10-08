# Changelog

## [0.15.1](https://github.com/ldonnez/memo.nvim/compare/v0.15.0...v0.15.1) (2026-10-08)


### Code Refactoring

* track a new note's encryption mode in a write closure ([b4fb6e4](https://github.com/ldonnez/memo.nvim/commit/b4fb6e435fea377bf91c5d7efa85ba99b6ad6296))

## [0.15.0](https://github.com/ldonnez/memo.nvim/compare/v0.14.2...v0.15.0) (2026-10-07)


### Features

* **capture:** allow captures with a encryption mode ([c1a2269](https://github.com/ldonnez/memo.nvim/commit/c1a22699c776d45ee2ac508baab54b07a418a038))
* create passphrase notes from new_note and save_as_note ([69bc967](https://github.com/ldonnez/memo.nvim/commit/69bc967295df87012968bb573d300e6f519db2fb))
* **scratch:** accept window and encryption opts ([7500750](https://github.com/ldonnez/memo.nvim/commit/7500750adbe9f6a898454d6f974add7549ef3900))
* **template:** extract initial content ([03e1990](https://github.com/ldonnez/memo.nvim/commit/03e1990e6253ef96efe2ed2f44e19a5047cc94e9))

## [0.14.2](https://github.com/ldonnez/memo.nvim/compare/v0.14.1...v0.14.2) (2026-10-05)


### Bug Fixes

* drop a cached note passphrase when its buffer is wiped ([575d542](https://github.com/ldonnez/memo.nvim/commit/575d5426c91bd2ea8701a9550f05d1c684c84f6e))
* ensure pinentry is not called twice when decrypting symmetric files ([92d721b](https://github.com/ldonnez/memo.nvim/commit/92d721bcefc98cc0abb80ea7421d4b371449872a))

## [0.14.1](https://github.com/ldonnez/memo.nvim/compare/v0.14.0...v0.14.1) (2026-10-04)


### Bug Fixes

* drop a trailing slash from the notes dir ([509a7a4](https://github.com/ldonnez/memo.nvim/commit/509a7a4b790cd6c36bfd35c27be5272bda88e641))
* leaves directory in the notes dir to the directory handler ([91315a6](https://github.com/ldonnez/memo.nvim/commit/91315a678710151c70bcc4ef1c0c0fb7a433a465))
* read back the configured note extension ([9ac483c](https://github.com/ldonnez/memo.nvim/commit/9ac483c92e54aa738137d0439bf870f033e5aa84))
* reject an empty capture file ([74606a9](https://github.com/ldonnez/memo.nvim/commit/74606a9dd04f2ebef39d67698076faccc624d4b6))

## [0.14.0](https://github.com/ldonnez/memo.nvim/compare/v0.13.0...v0.14.0) (2026-10-03)


### ⚠ BREAKING CHANGES

* write to .asc extension instead of .gpg

### Features

* add memo version check ([aad54c7](https://github.com/ldonnez/memo.nvim/commit/aad54c73ef96b7f89d0e7bb494814297d0615907))
* open notes that are encrypted with a passphrase ([14cd61d](https://github.com/ldonnez/memo.nvim/commit/14cd61d87689252c46dc9c3cf14b515db89b3759))


### Bug Fixes

* do not allow empty or directory paths ([5bfa8d5](https://github.com/ldonnez/memo.nvim/commit/5bfa8d5620b96a607eb60e834b13a3e21a2bf476))
* silently returns "" for invalid paths (empty, absolute, traversal) ([3d2343c](https://github.com/ldonnez/memo.nvim/commit/3d2343c67572ea460c495b088bb85aa276a8418a))


### Code Refactoring

* write to .asc extension instead of .gpg ([3725cac](https://github.com/ldonnez/memo.nvim/commit/3725cac0650c2f928659ed862c3c2aec901b2792))

## [0.13.0](https://github.com/ldonnez/memo.nvim/compare/v0.12.3...v0.13.0) (2026-09-29)


### ⚠ BREAKING CHANGES

* name the capture template option `template`

### Features

* add fzf-lua picker for current cwd scratch files ([f420ceb](https://github.com/ldonnez/memo.nvim/commit/f420ceb847901bb313518c352e9b5654009db059))
* add g:memo_default_capture_file and the :Memo command ([98b527b](https://github.com/ldonnez/memo.nvim/commit/98b527bb7235897ed2c7e805683d43ce474fb313))
* add memo.open for opening a note by path ([967d2bf](https://github.com/ldonnez/memo.nvim/commit/967d2bfbec93d5f41a33a76038e122c9d9ac656b))
* add MemoNewNote for creating encrypted notes ([74cab4e](https://github.com/ldonnez/memo.nvim/commit/74cab4e226e29be47e031d3470577d4f90c14297))
* ask to overwrite an existing note in MemoNewNote ([3a97552](https://github.com/ldonnez/memo.nvim/commit/3a97552358cfeed37d289ef72f395d48c9c94b3d))
* default every window option ([1c04c98](https://github.com/ldonnez/memo.nvim/commit/1c04c98da96166357c492767a952303103397df0))
* insert a selection at the new note template cursor ([795d178](https://github.com/ldonnez/memo.nvim/commit/795d178583577949c5a378d51a1a1fe7493255b6))
* keep the capture template when capturing a selection ([e7587cc](https://github.com/ldonnez/memo.nvim/commit/e7587ccdb3f12ea964f8aa4cb6c1fcaac76d2fee))
* make save_as_note work on visual selection ([b7c761b](https://github.com/ldonnez/memo.nvim/commit/b7c761b02b25081ff8b783a2f0bf5d043d340028))
* make the window size a share of the screen ([39b289d](https://github.com/ldonnez/memo.nvim/commit/39b289d5687dbd339b22bbb0aa2051985bdc3577))
* open a new note in a split ([b0a5f32](https://github.com/ldonnez/memo.nvim/commit/b0a5f326f06f3b970d444d840c638994a30ecdff))
* prompt for the note path from the Lua API too ([dc9bfa6](https://github.com/ldonnez/memo.nvim/commit/dc9bfa6ec3323cb6fcbdf91b1df1c22c55a99665))
* seed new notes from a range or visual selection ([0ab740a](https://github.com/ldonnez/memo.nvim/commit/0ab740a483c5848d4713b61361830b781a511402))
* show readable cwd paths for scratch files in fzf-lua pickers ([c87e81b](https://github.com/ldonnez/memo.nvim/commit/c87e81b1365073d42131bc3d3d53b7f92e56e3f6))
* support opening a note in a tab ([c1dae5c](https://github.com/ldonnez/memo.nvim/commit/c1dae5c1577d25930b886b382ac77e7839054da3))


### Code Refactoring

* name the capture template option `template` ([5dd2fc0](https://github.com/ldonnez/memo.nvim/commit/5dd2fc099d070cc710f80a573e7a9c6aa8d39341))

## [0.12.3](https://github.com/ldonnez/memo.nvim/compare/v0.12.2...v0.12.3) (2026-09-20)


### Bug Fixes

* always decrypt gpg path ([5f5b94b](https://github.com/ldonnez/memo.nvim/commit/5f5b94b0fa10e50e612e6409749dd983c5e13968))
* always normalize buffer file to absolute path ([1dfb613](https://github.com/ldonnez/memo.nvim/commit/1dfb613e4a625d83ac85c916b41954c9e594b01c))
* **ci:** ensure checkout of same ref ([ae36338](https://github.com/ldonnez/memo.nvim/commit/ae3633882d7a21337c1bcc62d60ccbdbea398bce))
* defer error message ([e30fa4d](https://github.com/ldonnez/memo.nvim/commit/e30fa4db30dd30aff243671c21bafba15d194fca))
* don't delete gpg files in a similarly named directory ([d80e8aa](https://github.com/ldonnez/memo.nvim/commit/d80e8aae78503ea3d1e33d475cad2d487599ad7d))
* ensure capture window does not freeze when gpg errors occur ([3253b44](https://github.com/ldonnez/memo.nvim/commit/3253b44edd22476076194ba7af45e34132f9ad62))
* safely ignores the result when the buffer was closed ([90ddac4](https://github.com/ldonnez/memo.nvim/commit/90ddac42145d80f3414afe61043032c9cc2a749f))
* wipe buffer when gpg authentication fails ([e6d9234](https://github.com/ldonnez/memo.nvim/commit/e6d9234ef2d19691d845adb9e87a300fdb000eb2))

## [0.12.2](https://github.com/ldonnez/memo.nvim/compare/v0.12.1...v0.12.2) (2026-09-20)


### Documentation

* improve README to be consistent with vim docs ([90196bb](https://github.com/ldonnez/memo.nvim/commit/90196bbbf0158cdbc0d0575c8a57c8e349c27a50))

## [0.12.1](https://github.com/ldonnez/memo.nvim/compare/v0.12.0...v0.12.1) (2026-09-19)


### Bug Fixes

* avoid overlapping notes and scratch patterns in autocmd ([e733a32](https://github.com/ldonnez/memo.nvim/commit/e733a32aa4b37b85b74665510694a74607a5036c))
* only delete scratch files matching a pattern ([89cdbef](https://github.com/ldonnez/memo.nvim/commit/89cdbef639ed58f5771d89c3f6e9e9abf870af72))

## [0.12.0](https://github.com/ldonnez/memo.nvim/compare/v0.11.1...v0.12.0) (2026-09-19)


### Features

* add ignore patterns ([99ef65a](https://github.com/ldonnez/memo.nvim/commit/99ef65af2f8e4174039c1112ce1eea6ac9b1c2ad))

## [0.11.1](https://github.com/ldonnez/memo.nvim/compare/v0.11.0...v0.11.1) (2026-09-18)


### Bug Fixes

* ensure file path completion ([84d12d3](https://github.com/ldonnez/memo.nvim/commit/84d12d31f4f5fa115a4c97ded2b550f65220bcb1))

## [0.11.0](https://github.com/ldonnez/memo.nvim/compare/v0.10.0...v0.11.0) (2026-09-15)


### Features

* ask to overwrite when note already exists ([d754a9d](https://github.com/ldonnez/memo.nvim/commit/d754a9dc7805c6ebf19ce1ee920f6abce6b7d3c7))

## [0.10.0](https://github.com/ldonnez/memo.nvim/compare/v0.9.0...v0.10.0) (2026-09-14)


### Features

* don't delete scratch buffer when saving as note ([8d4a9b1](https://github.com/ldonnez/memo.nvim/commit/8d4a9b19caa26447967d23e91ab3a836b6c40da1))
* make scratch dir configurable with vim.g.memo_scratch_dir option ([b77666a](https://github.com/ldonnez/memo.nvim/commit/b77666afc07c891dc7eb415ecb85d2c69ada4150))
* show note path when saving buffer as note ([298fb68](https://github.com/ldonnez/memo.nvim/commit/298fb68c6f098701d7a13a9ea9aeff6422179705))

## [0.9.0](https://github.com/ldonnez/memo.nvim/compare/v0.8.0...v0.9.0) (2026-09-13)


### ⚠ BREAKING CHANGES

* drop conform integration

### Features

* add :MemoFiles cmd ([4adba6b](https://github.com/ldonnez/memo.nvim/commit/4adba6bb23eb016ae48e38c9c00a29d4bd35e992))
* add fzf-lua picker for scratch files ([bcda9ad](https://github.com/ldonnez/memo.nvim/commit/bcda9ad7b8ea172711340a362be761d92a7815d3))
* add save to note ([55b8c63](https://github.com/ldonnez/memo.nvim/commit/55b8c63051310c593bef37ea20f36fe479342fb0))
* capture with range selection ([9abc5bd](https://github.com/ldonnez/memo.nvim/commit/9abc5bd7e60392ec1eab01ccb47abdcccb5bfb22))
* encrypt any filetype in notes dir ([b39912b](https://github.com/ldonnez/memo.nvim/commit/b39912b1b568d3eca2c7732f00cfe53ebdd4395d))
* encrypted scratch buffers ([2e4d767](https://github.com/ldonnez/memo.nvim/commit/2e4d767f9e73a3eccb1c64dc98e9b29e8f383832))


### Code Refactoring

* drop conform integration ([d01d747](https://github.com/ldonnez/memo.nvim/commit/d01d747da07a4ff1be0bd3ada7a46ebbfab9b547))

## [0.8.0](https://github.com/ldonnez/memo.nvim/compare/v0.7.2...v0.8.0) (2026-05-26)


### ⚠ BREAKING CHANGES

* remove TODO picker logic

### Code Refactoring

* remove TODO picker logic ([e523150](https://github.com/ldonnez/memo.nvim/commit/e523150da8afd4e94ef22178c0dc46fff8703923))

## [0.7.2](https://github.com/ldonnez/memo.nvim/compare/v0.7.1...v0.7.2) (2026-05-05)


### Features

* show key name and email when asking for GPG passphrase ([330d20a](https://github.com/ldonnez/memo.nvim/commit/330d20a3f751497bb7edd46ceabe04dc08c98cd3))


### Bug Fixes

* correctly handle opening existing unencrypted file in notes dir ([ce461d9](https://github.com/ldonnez/memo.nvim/commit/ce461d949e4aac4b0b3341180108b5633e8af59e))
* ensure looking for exact key ID ([2e8fb09](https://github.com/ldonnez/memo.nvim/commit/2e8fb09cc8c2c6f931b894183b5bd5fbb40f8315))
* remove unnecessary colon when asking for passphrase ([170e67c](https://github.com/ldonnez/memo.nvim/commit/170e67c419e9ae9cc259ec70764dd9bde2a290c3))

## [0.7.1](https://github.com/ldonnez/memo.nvim/compare/v0.7.0...v0.7.1) (2026-05-04)


### Bug Fixes

* ensure correct autocmd events fire when reading/writing buffer ([82d71b6](https://github.com/ldonnez/memo.nvim/commit/82d71b6867fae671ccf5fee4869fbef716715a7e))

## [0.7.0](https://github.com/ldonnez/memo.nvim/compare/v0.6.1...v0.7.0) (2026-04-25)


### Features

* conform.nvim integration ([6b480dc](https://github.com/ldonnez/memo.nvim/commit/6b480dc8943302c8caed5ccfd12c0e31f5fdace5))

## [0.6.1](https://github.com/ldonnez/memo.nvim/compare/v0.6.0...v0.6.1) (2026-04-21)


### Bug Fixes

* don't set buffer type to acwrite ([8ff077e](https://github.com/ldonnez/memo.nvim/commit/8ff077e07917a19b433f0def92b8f25bb40dca3a))

## [0.6.0](https://github.com/ldonnez/memo.nvim/compare/v0.5.0...v0.6.0) (2026-04-11)


### ⚠ BREAKING CHANGES

* correctly lazy load plugin

### Features

* correctly lazy load plugin ([6182cbe](https://github.com/ldonnez/memo.nvim/commit/6182cbecc1f94e7c22a8be9a9df3566ba58a2e6d))


### Bug Fixes

* ensure correct type ([2029042](https://github.com/ldonnez/memo.nvim/commit/20290421a23eec41cb0d1004f653beeba17c6a9f))

## [0.5.0](https://github.com/ldonnez/memo.nvim/compare/v0.4.0...v0.5.0) (2026-01-12)


### Features

* **picker:** add multi-select support for quickfix export ([038b49c](https://github.com/ldonnez/memo.nvim/commit/038b49c13540255122f1dc713e080c7e2aa06a38))

## [0.4.0](https://github.com/ldonnez/memo.nvim/compare/v0.3.3...v0.4.0) (2026-01-11)


### ⚠ BREAKING CHANGES

* move fzf-lua files picker to pickers/fzf_lua.lua

### Features

* add fzf-lua picker to find todos in current buffer ([5ef1174](https://github.com/ldonnez/memo.nvim/commit/5ef1174c5d85bef2a600614c334f83e561c768d8))


### Code Refactoring

* move fzf-lua files picker to pickers/fzf_lua.lua ([71d9b4a](https://github.com/ldonnez/memo.nvim/commit/71d9b4acf6dca2ab9b723e315a7e5456fc278198))

## [0.3.3](https://github.com/ldonnez/memo.nvim/compare/v0.3.2...v0.3.3) (2026-01-04)


### Bug Fixes

* ensure no new lines are added when capturing ([5059b13](https://github.com/ldonnez/memo.nvim/commit/5059b13fd159d937ff6eaa53121c0d7a890378f8))
* ensure no new lines are appended when decrypting ([aeeb756](https://github.com/ldonnez/memo.nvim/commit/aeeb7561810455a8c77cb02d5f7718a7088e1021))
* ensure utf-8 encoding on buffers ([50ccfc9](https://github.com/ldonnez/memo.nvim/commit/50ccfc97ff14ffdcff0e60cd9ed93d500d253fb5))

## [0.3.2](https://github.com/ldonnez/memo.nvim/compare/v0.3.1...v0.3.2) (2026-01-02)


### Bug Fixes

* ensure loading encrypted buffers acts the same regular opening ([5e29968](https://github.com/ldonnez/memo.nvim/commit/5e29968d2ee30af9d7a8d4f07ac2ad92a8c08928))


### Code Refactoring

* simplify decrypting state ([3de4031](https://github.com/ldonnez/memo.nvim/commit/3de4031247231e124712410d6c772dd73d025282))

## [0.3.1](https://github.com/ldonnez/memo.nvim/compare/v0.3.0...v0.3.1) (2025-12-31)


### Bug Fixes

* don't write to buffer while decrypting ([c5303a6](https://github.com/ldonnez/memo.nvim/commit/c5303a6d54a1943abda64d9b5b681a8d76ec5658))

## [0.3.0](https://github.com/ldonnez/memo.nvim/compare/v0.2.0...v0.3.0) (2025-12-31)


### Features

* make capture window size and position configurable ([5da155e](https://github.com/ldonnez/memo.nvim/commit/5da155ec63b2e0864e5228cd3e13ed1e1ee2f4b2))

## [0.2.0](https://github.com/ldonnez/memo.nvim/compare/v0.1.1...v0.2.0) (2025-12-30)


### Features

* abort capture when window is empty or only contains header ([32eb2ea](https://github.com/ldonnez/memo.nvim/commit/32eb2ea7b9699a4976c2241d98f3a4afbbf05fb8))
* add basic capture templating ([58995a5](https://github.com/ldonnez/memo.nvim/commit/58995a5c3ef4fc7b819d42099ce52000cc761d14))
* add check for memo ([6e08f86](https://github.com/ldonnez/memo.nvim/commit/6e08f8607fb14174cd934e9ee7ffa0c32e6d0849))
* don't reencrypt buffer when no changes are made ([a6ce746](https://github.com/ldonnez/memo.nvim/commit/a6ce7468d5194ed11ba0c3d18189f4e1f035ea52))
* ensure git sync can be called by lua function ([72295f6](https://github.com/ldonnez/memo.nvim/commit/72295f6645555994a6bde64df574415c44dfe02f))
* ensure multiple keys work when asking for gpg password ([9b9cdfa](https://github.com/ldonnez/memo.nvim/commit/9b9cdfa4684939f1b495387647e258ef0b396813))
* ensure relative directories from capture file are created ([0e6830b](https://github.com/ldonnez/memo.nvim/commit/0e6830bddf295541025d92089e1044ecf176a285))
* make encryption/decryption non blocking ([54842cd](https://github.com/ldonnez/memo.nvim/commit/54842cd0111d0745b54948dc598fb3325f1f7a7d))


### Bug Fixes

* correctly determine filetype ([02e7cb0](https://github.com/ldonnez/memo.nvim/commit/02e7cb08135c111a459fd5969a9113fa245a9584))
* don't decrypt when file is empty or does not exist ([ab86a27](https://github.com/ldonnez/memo.nvim/commit/ab86a272bebfbb846cb68af5073c3e6423534218))
* don't expand default capture file opts with notes_dir ([a016662](https://github.com/ldonnez/memo.nvim/commit/a01666266d333fa9082202fcd501378c5de391e7))
* don't trigger decryption on non encrypted files ([98fe3cf](https://github.com/ldonnez/memo.nvim/commit/98fe3cf8b8c58a7b3bd3aeb44f441c86a3193a24))
* ensure correct filetype detection ([03172c1](https://github.com/ldonnez/memo.nvim/commit/03172c16905d4c175240908ac5c6f42a37900f80))
* ensure correct message ([ce9d695](https://github.com/ldonnez/memo.nvim/commit/ce9d69584e4a4a6a462452d48afa727d02d96268))
* ensure to strip empty lines from buffer ([b2c6df3](https://github.com/ldonnez/memo.nvim/commit/b2c6df34bf267252b84a7d4cc01fb9d3856bac38))
* immediately create capture file when it does not exist ([402f930](https://github.com/ldonnez/memo.nvim/commit/402f930d3f626825c0f9a16dd95d031f33188857))

## [0.1.1](https://github.com/ldonnez/memo.nvim/compare/v0.1.0...v0.1.1) (2025-12-24)


### Features

* decrypt and load when force editing file ([97d042a](https://github.com/ldonnez/memo.nvim/commit/97d042aa9a6df5a737160be9e3bbdc875a90dadc))


### Bug Fixes

* correct error message ([bbfd317](https://github.com/ldonnez/memo.nvim/commit/bbfd317b8af23c25615dddd82b2dd7426ce23483))
* correctly reload buffer when creating new file ([f9b4375](https://github.com/ldonnez/memo.nvim/commit/f9b437552626996f94c07a17513dc4614308372f))
* don't set buffer name when it already exists ([d204388](https://github.com/ldonnez/memo.nvim/commit/d204388844bf1456a1e0b9085996a9e1d322170a))
* prevent double buffer writes ([f618376](https://github.com/ldonnez/memo.nvim/commit/f6183760862474a886c96ac396671172ce41deb5))


### Code Refactoring

* use builtin fzf-lua files picker ([ae05abe](https://github.com/ldonnez/memo.nvim/commit/ae05abe30811d4853ee17a1b129a6e7428a9cf58))

## [0.1.0](https://github.com/ldonnez/memo.nvim/compare/v0.0.1...v0.1.0) (2025-12-23)


### Miscellaneous Chores

* **main:** add release please ([5f948af](https://github.com/ldonnez/memo.nvim/commit/5f948af22aacf1ba6a6c15b7bcd63ccea627b117))
