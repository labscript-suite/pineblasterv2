import bitblaster, numpy
with bitblaster.BitBlaster("COM5") as dev:
	# here's a basic clocking example
	# dev.bitstream(numpy.arange(100)%16,2e-7)
	# a more interesting random example
	dev.bitstream(numpy.random.randint(0,32,100),150e-9)
	dev.start(wait=True)
