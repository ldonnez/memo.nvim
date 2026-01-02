# Changelog

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
