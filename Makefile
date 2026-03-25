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
	logo.s

COPT = -C -Wall -Werror -Wno-shadow -Wno-implied-reg -Wno-strict-bool -x --verbose-list -I .

pexec.bin: $(SRCS)
	64tass $(COPT) pexec.s -b -L $(basename $@).lst -o $@

run: pexec.bin
	foenixmgr binary pexec.bin --address 0xA000

flash: pexec.bin
	foenixmgr flash-bulk update.csv

clean:
	rm -f pexec.bin pexec.lst
