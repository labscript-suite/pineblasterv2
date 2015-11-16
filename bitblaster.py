"""
bitblaster python interface
http://bitbucket.com/martijnj/bitblaster
Copyright 2015 by Martijn Jasperse
"""
import serial
import time

CLOCK = 40e6
BAUDRATE = 115200
CRLF = '\r\n'

class BitBlaster:
	def __init__(self,port,timeout=1,startup=5):
		"""Establish connection with a bitblaster unit at the specified serial port.
		The serial interface timeout is `timeout` and the maximum startup delay is `startup`."""
		# connect to device
		self._ser = serial.Serial(port,BAUDRATE,timeout=timeout)
		self.wait(startup,'ready')
		# make sure connection works
		self.check('hello','hello')
		
	def __enter__(self):
		return self
	
	def __exit__(self, type, value, traceback):
		self._ser.close()
		
	def write(self,cmd):
		"""Write the specified command to the unit."""
		if not cmd.endswith(CRLF):	# must CRLF terminate
			cmd = cmd + CRLF
		self._ser.write(cmd)
		
	def read(self):
		"""Read back from unit, and trim whitespace."""
		return self._ser.readline().strip()
		
	def check(self,cmd,expect='ok'):
		"""Send the command, get a reply, make sure it matches expectation."""
		self.write(cmd)
		resp = self.read()
		if not resp == expect:
			raise self.SerialError('Unexpected response: '+resp)
			
	def bitstream(self,vals,dt=None,timesteps=False,adapt=True):
		"""Program the unit to output the values in `vals` every `dt` seconds.
		If `timesteps` is True, `dt` is specified in clock cycles not seconds.
		If `adapt` is True, the timesteps are adjusted to minimise cumulative timing error."""
		# parse parameters
		if timesteps: dt = dt / CLOCK
		# program the sequence
		return self.sequence([(v,dt) for v in vals],adapt=adapt)
		
	def sequence(self,vals,n0=0,adapt=True):
		"""Program the unit with the given sequence.
		The sequence is an iterable of tuples (v,dt) where `v` is the value to output and `dt` the time to maintain that output in seconds.
		If `adapt` is True, the timesteps are adjusted to minimise cumulative timing error.
		Note that `dt`==0 causes the device to wait for a hardware trigger."""
		n = 0
		err = 0
		for v, dt in vals:
			# adapt the timestep to the cumulative error?
			if adapt: dt -= err
			# guess closest number of steps
			di = int(round(dt*CLOCK))
			assert di >= 6, 'Timestep too small'
			# accumulate error
			err += dt - di/CLOCK
			# program sequence, allow for long timesteps
			for i in range(di//65535):
				# potential error if di%65535 < 6
				self.check('set %i %x %u'%(n,v,65535))
				n += 1
			self.check('set %i %x %u'%(n,v,di%65535))
			n += 1
		# make sure to terminate the sequence
		self.check('set %i 0 0'%n)
		# check it worked
		self.check('len',str(n))
		return n
		
	def start(self,hwtrig=False,wait=None):
		"""Send the unit the "start" command.
		If `hwtrig` is true, the unit will wait for a hardware trigger.
		If `wait` is not None, the function waits until the sequence completes using wait()."""
		if hwtrig:
			self.check('hwstart')	# start on ext trigger
		else:
			self.check('start')		# software trigger now
		if wait is None:
			return					# do not wait
		if isinstance(wait,bool):
			if wait:
				return self.wait()	# wait forever
			else:
				return				# do not wait
		else:
			return self.wait(wait)	# wait for specified timeout
	
	def wait(self,timeout=None,expect='done'):
		"""Waits for the unit to return "done" at the end of a sequence.
		A RuntimeError is raised if the sequence does not terminate within `timeout` seconds.
		If `timeout` is None, the function waits forever."""
		bailout = int(time.time()+timeout*1000) if timeout is not None else None
		while True:
			resp = self.read()
			if resp == expect:
				return
			elif resp != '':
				raise self.SerialError('Unexpected response: '+resp)
			if bailout is not None and time.time() > bailout:
				raise RuntimeError('Timeout')
			time.sleep(5e-3)
