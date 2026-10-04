# Main Makefile for DOSBox-X

EXTRA_DIST = autogen.sh
SUBDIRS = src include

dosboxdatadir = $(datadir)/dosbox-x
drivezdir = $(dosboxdatadir)/drivez
glshadersdir = $(dosboxdatadir)/glshaders
languagesdir = $(dosboxdatadir)/languages
iconscalabledir = $(datadir)/icons/hicolor/scalable/apps
desktopdir = $(datadir)/applications
metainfodir = $(datadir)/metainfo
bashcompletiondir = $(datadir)/bash-completion/completions

dist_glshaders_DATA = \
	contrib/glshaders/ScanLine.glsl \
	contrib/glshaders/advinterp2x.glsl \
	contrib/glshaders/advinterp3x.glsl \
	contrib/glshaders/advmame2x.glsl \
	contrib/glshaders/advmame3x.glsl \
	contrib/glshaders/crt-aperture.glsl \
	contrib/glshaders/crt-caligari.glsl \
	contrib/glshaders/crt-easymode.glsl \
	contrib/glshaders/crt-easymode.tweaked.glsl \
	contrib/glshaders/crt-geom.glsl \
	contrib/glshaders/crt-geom.tweaked.glsl \
	contrib/glshaders/crt-hyllian.glsl \
	contrib/glshaders/crt-lottes-fast.glsl \
	contrib/glshaders/crt-lottes-fast.subtle+gain.glsl \
	contrib/glshaders/crt-lottes.glsl \
	contrib/glshaders/crt-lottes.tweaked.glsl \
	contrib/glshaders/crt-nes-mini.glsl \
	contrib/glshaders/crt-pi.glsl \
	contrib/glshaders/default.glsl \
	contrib/glshaders/fakelottes.glsl \
	contrib/glshaders/fakelottes.tweaked.glsl \
	contrib/glshaders/none.glsl \
	contrib/glshaders/pixel_perfect-scanlines.glsl \
	contrib/glshaders/pixel_perfect.glsl \
	contrib/glshaders/pixellate.glsl \
	contrib/glshaders/rgb2x.glsl \
	contrib/glshaders/rgb3x.glsl \
	contrib/glshaders/scan2x.glsl \
	contrib/glshaders/scan3x.glsl \
	contrib/glshaders/sharp.glsl \
	contrib/glshaders/tv2x.glsl \
	contrib/glshaders/tv3x.glsl \
	contrib/glshaders/xbr-lv2-3d.glsl \
	contrib/glshaders/xbr-lv2-noblend.glsl \
	contrib/glshaders/xbr-lv2.glsl \
	contrib/glshaders/xbr-lv3.glsl \
	contrib/glshaders/yee64.glsl \
	contrib/glshaders/yeetron.glsl \
	contrib/glshaders/zfast_crt.glsl

dist_languages_DATA = \
	contrib/translations/ca/ca_ES.lng \
	contrib/translations/de/de_DE.lng \
	contrib/translations/de/de_pc98.lng \
	contrib/translations/en/en_US.lng \
	contrib/translations/es/es_ES.lng \
	contrib/translations/fr/fr_FR.lng \
	contrib/translations/hu/hu_HU.lng \
	contrib/translations/it/it_IT.lng \
	contrib/translations/ja/ja_JP.lng \
	contrib/translations/ko/ko_KR.lng \
	contrib/translations/nl/nl_NL.lng \
	contrib/translations/pt/pt_BR.lng \
	contrib/translations/ru/ru_RU.lng \
	contrib/translations/tr/tr_TR.lng \
	contrib/translations/zh/zh_CN.lng \
	contrib/translations/zh/zh_TW.lng

dist_iconscalable_DATA = contrib/icons/dosbox-x.svg
dist_desktop_DATA = contrib/linux/com.dosbox_x.DOSBox-X.desktop
dist_metainfo_DATA = contrib/linux/com.dosbox_x.DOSBox-X.metainfo.xml
dist_bashcompletion_DATA = contrib/linux/dosbox-x
dist_man_MANS = contrib/linux/dosbox-x.1

if MACOSX
if MACOS_UNIVERSAL
MACOS_BINARIES=src/dosbox-x-arm64 src/dosbox-x-x86_64
else
MACOS_BINARIES=src/dosbox-x-$(MACOSX_CPU)
endif
endif

.PHONY: dosbox-x.app

dosbox-x.app: $(MACOS_BINARIES) contrib/macos/dosbox.icns src/tool/mach-o-matic
	rm -Rfv dosbox-x.app
	mkdir dosbox-x.app
	mkdir dosbox-x.app/Contents
	mkdir dosbox-x.app/Contents/MacOS
	mkdir dosbox-x.app/Contents/MacOS/arm64
	mkdir dosbox-x.app/Contents/MacOS/x86_64
	mkdir dosbox-x.app/Contents/Resources
	mkdir dosbox-x.app/Contents/Resources/drivez
	mkdir dosbox-x.app/Contents/Resources/glshaders
	mkdir dosbox-x.app/Contents/Resources/languages
	cp -v contrib/macos/dosbox-x.plist dosbox-x.app/Contents/Info.plist
	cp -v contrib/macos/dosbox-x.pkginfo dosbox-x.app/Contents/PkgInfo
	cp -v contrib/macos/dosbox.icns dosbox-x.app/Contents/Resources/dosbox-x.icns
	cp -v contrib/fonts/FREECG98.BMP dosbox-x.app/Contents/Resources/freecg98.bmp
	cp -v contrib/fonts/wqy_1?pt.bdf dosbox-x.app/Contents/Resources/
	cp -v contrib/fonts/Nouveau_IBM.ttf dosbox-x.app/Contents/Resources/Nouveau_IBM.ttf
	cp -v contrib/fonts/SarasaGothicFixed.ttf dosbox-x.app/Contents/Resources/SarasaGothicFixed.ttf
	cp -v contrib/windows/installer/drivez_readme.txt dosbox-x.app/Contents/Resources/drivez/readme.txt
	cp -v contrib/glshaders/* dosbox-x.app/Contents/Resources/glshaders/
	cp -v contrib/translations/*/*.lng dosbox-x.app/Contents/Resources/languages/
	cp -v dosbox-x.reference.conf dosbox-x.app/Contents/Resources/
	cp -v dosbox-x.reference.full.conf dosbox-x.app/Contents/Resources/
	if [ -f src/dosbox-x-arm64 ]; then cp -v src/dosbox-x-arm64 dosbox-x.app/Contents/MacOS/arm64/dosbox-x; fi
	if [ -f src/dosbox-x-x86_64 ]; then cp -v src/dosbox-x-x86_64 dosbox-x.app/Contents/MacOS/x86_64/dosbox-x; fi
# Find all dependencies of the binary. This time we have a Python script to find them all, so it is not as ugly.
# Find dependent libraries and copy them into the app bundle separated by architecture
	@for exe in dosbox-x.app/Contents/MacOS/arm64/dosbox-x dosbox-x.app/Contents/MacOS/x86_64/dosbox-x; do \
		if [ -f "$$exe" ]; then \
			./appbundledeps.py --exe "$$exe" | while read R; do \
				Y=$$(printf '%s\n' "$$R" | cut -f 1); \
				dylib=$$(printf '%s\n' "$$R" | cut -f 2); \
				echo "Copying $$dylib"; \
				if echo $$Y | grep -Eq '/opt/homebrew'; then \
					cp -v $$Y dosbox-x.app/Contents/MacOS/arm64/$$dylib; \
					codesign --remove-signature "dosbox-x.app/Contents/MacOS/arm64/$$dylib" || exit 1; \
					chmod 0755 "dosbox-x.app/Contents/MacOS/arm64/$$dylib" || exit 1; \
				else \
					cp -v $$Y dosbox-x.app/Contents/MacOS/x86_64/$$dylib; \
					codesign --remove-signature "dosbox-x.app/Contents/MacOS/x86_64/$$dylib" || exit 1; \
					chmod 0755 "dosbox-x.app/Contents/MacOS/x86_64/$$dylib" || exit 1; \
				fi; \
			done; \
		fi; \
	done
# Fix the linker search paths of the libraries we copied
	@for dir in dosbox-x.app/Contents/MacOS/arm64 dosbox-x.app/Contents/MacOS/x86_64; do \
		if ls "$$dir"/*.dylib >/dev/null 2>&1; then \
			arpf=$$(basename "$$dir"); \
			for dylib in $$dir/*.dylib; do \
				[ -f "$$dylib" ] && (ARCHPREF=$$arpf src/tool/mach-o-matic "$$dylib") || exit 1; \
			done; \
		fi; \
	done
# Remove the signatures from the architecture-dependant executables, and fix their linker search paths.
	@if [ -f dosbox-x.app/Contents/MacOS/arm64/dosbox-x ]; then \
		export ARCHPREF=arm64; \
		codesign --remove-signature dosbox-x.app/Contents/MacOS/arm64/dosbox-x || exit 1; \
		src/tool/mach-o-matic dosbox-x.app/Contents/MacOS/arm64/dosbox-x || exit 1; \
	fi
	@if [ -f dosbox-x.app/Contents/MacOS/x86_64/dosbox-x ]; then \
		export ARCHPREF=x86_64; \
		codesign --remove-signature dosbox-x.app/Contents/MacOS/x86_64/dosbox-x || exit 1; \
		src/tool/mach-o-matic dosbox-x.app/Contents/MacOS/x86_64/dosbox-x || exit 1; \
	fi
# Create universal binary executable if both architectures are present or just move the one we have
	@if [ -f dosbox-x.app/Contents/MacOS/arm64/dosbox-x ] && [ -f dosbox-x.app/Contents/MacOS/x86_64/dosbox-x ]; then \
		lipo -create dosbox-x.app/Contents/MacOS/arm64/dosbox-x dosbox-x.app/Contents/MacOS/x86_64/dosbox-x -output dosbox-x.app/Contents/MacOS/dosbox-x; \
		rm -f dosbox-x.app/Contents/MacOS/arm64/dosbox-x dosbox-x.app/Contents/MacOS/x86_64/dosbox-x; \
	elif [ -f dosbox-x.app/Contents/MacOS/arm64/dosbox-x ]; then \
		mv -f dosbox-x.app/Contents/MacOS/arm64/dosbox-x dosbox-x.app/Contents/MacOS/dosbox-x; \
	elif [ -f dosbox-x.app/Contents/MacOS/x86_64/dosbox-x ]; then \
		mv -f dosbox-x.app/Contents/MacOS/x86_64/dosbox-x dosbox-x.app/Contents/MacOS/dosbox-x; \
	fi
# Re-sign the universal binary executable and all the libraries
	codesign --deep -s - dosbox-x.app/Contents/MacOS/dosbox-x || exit 1

debug-dosbox-x-app:
	(cd dosbox-x.app/Contents/MacOS && (DYLD_PRINT_LIBRARIES=1 ./dosbox-x -defaultconf -defaultdir . -silent -c 'echo hello' -c 'exit')) 2>mac-os-x-dylib-report.txt
	@echo 'Please review mac-os-x-dylib-report.txt to make sure the .app bundle loaded only from the executable path and not any external Brew libraries.'
	@echo 'This is crucial to maintain the ability to distribute this application in the Mac OS X world.'

src/tool/mach-o-matic: src/tool/mach-o-matic.cpp
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ $< $(LDFLAGS)

clean-local:
	rm -f src/tool/mach-o-matic

contrib/macos/dosbox.icns: contrib/macos/dosbox-x.png
	rm -Rfv src/dosbox.iconset
	mkdir src/dosbox.iconset
	sips -z 16 16     contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_16x16.png
	sips -z 32 32     contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_16x16@2.png
	sips -z 32 32     contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_32x32.png
	sips -z 128 128   contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_128x128.png
	sips -z 256 256   contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_256x256.png
	sips -z 512 512   contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_512x512.png
	sips -z 1024 1024 contrib/macos/dosbox-x.png    --out src/dosbox.iconset/icon_1024x1024.png

	iconutil -c icns -o contrib/macos/dosbox.icns src/dosbox.iconset
	rm -Rfv src/dosbox.iconset

dox:
	rm -Rfv doxygen
	doxygen

dox-site-update:
	if [ ! -d ../dosbox-x-gh-pages ]; then git clone -b gh-pages https://github.com/joncampbell123/dosbox-x.git ../dosbox-x-gh-pages; fi
	(cd ../dosbox-x-gh-pages && rm -Rfv doxygen)
	cp -Rf doxygen ../dosbox-x-gh-pages/
	(cd ../dosbox-x-gh-pages && git add doxygen/)
	(cd ../dosbox-x-gh-pages && git commit doxygen/)

compat-site-update:
	if [ ! -d ../dosbox-x-gh-pages ]; then git clone -b gh-pages https://github.com/joncampbell123/dosbox-x.git ../dosbox-x-gh-pages; fi
	true # ----------
	(cd /mnt/main/emu/demotest && ./make-compat-chart.pl)
	cp /mnt/main/emu/demotest/compat-chart.html ../dosbox-x-gh-pages/demoscene-compat.html
	true # ----------
	(cd /mnt/main/emu/msdostest && ./make-compat-chart.pl)
	cp /mnt/main/emu/msdostest/compat-chart.html ../dosbox-x-gh-pages/msdos-compat.html
	true # ----------
	(cd ../dosbox-x-gh-pages && git add demoscene-compat.html)
	(cd ../dosbox-x-gh-pages && git add msdos-compat.html)
	(cd ../dosbox-x-gh-pages && git commit -m 'more' msdos-compat.html demoscene-compat.html)

install-data-hook:
	$(MKDIR_P) "$(DESTDIR)$(drivezdir)"
	$(INSTALL_DATA) "$(srcdir)/contrib/windows/installer/drivez_readme.txt" "$(DESTDIR)$(drivezdir)/readme.txt"

install-exec-hook:
	-command -v setcap >/dev/null 2>&1 && setcap cap_net_raw=ep "$(DESTDIR)$(bindir)/dosbox-x"

uninstall-hook:
	rm -f "$(DESTDIR)$(drivezdir)/readme.txt"
	-rmdir "$(DESTDIR)$(drivezdir)" "$(DESTDIR)$(glshadersdir)" "$(DESTDIR)$(languagesdir)" "$(DESTDIR)$(dosboxdatadir)"
