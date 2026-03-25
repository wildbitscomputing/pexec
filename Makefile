SRCS = \
	pexec.s \
	kernel_api.s \
	mmu.s \
	term.s \
	lbm.s \
	i256.s \
	lzsa2.s \
	file.s \
	glyphs.s \
	colors.s \
	logo.s \
	chooser.s

COPT = -C -Wall -Werror -Wno-shadow -Wno-implied-reg -Wno-strict-bool -x --verbose-list -I .

pexec.bin: $(SRCS)
	64tass $(COPT) pexec.s -b -L $(basename $@).lst -o $@

run: pexec.bin
	foenixmgr binary pexec.bin --address 0xA000

flash: pexec.bin
	foenixmgr flash --address 380000 --flash-sector 08 --target f256k pexec.bin

MAME_PATH=../mame
IMAGE=$(MAME_PATH)/toolkit.img

emu: pexec.bin
	cp pexec.bin $(MAME_PATH)/roms/f256k/pexec.bin
	rm -f $(MAME_PATH)/nvram/f256k/flash
	cd $(MAME_PATH) && ./f256k f256k -window -resolution 1280x720 -skip_gameinfo -harddisk $(IMAGE) -rompath roms

clean:
	rm -f pexec.bin pexec.lst
