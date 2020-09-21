CC=gcc
#CC=arm-linux-gnueabihf-gcc
# adjust CCFLAGS for particular architecture
CCFLAGS='-mthumb -O3 -march=armv7-a -mcpu=cortex-a9 -mtune=cortex-a9 -mfpu=neon -mvectorize-with-neon-quad -mfloat-abi=hard -ffast-math'
CCFLAGS='-O3'
CCFLAGS='-Ofast'

${CC} ${CCFLAGS} -c demod_mod.c
${CC} ${CCFLAGS} -c bch_ecc_mod.c
${CC} ${CCFLAGS} rs41mod.c demod_mod.o bch_ecc_mod.o -lm -o rs41mod
${CC} ${CCFLAGS} dfm09mod.c demod_mod.o -lm -o dfm09mod
${CC} ${CCFLAGS} m10mod.c demod_mod.o -lm -o m10mod
${CC} ${CCFLAGS} lms6mod.c demod_mod.o bch_ecc_mod.o -lm -o lms6mod
${CC} ${CCFLAGS} rs92mod.c demod_mod.o bch_ecc_mod.o -lm -o rs92mod #` (needs `RS/rs92/nav_gps_vel.c`)
${CC} ${CCFLAGS} c50dft.c -lm -o c50dft
${CC} ${CCFLAGS} c34dft.c -lm -o c34dft
${CC} ${CCFLAGS} dft_detect.c -lm -o dft_detect
