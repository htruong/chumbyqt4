/* tonegen.c - Generate single, dual, or Touch Tone tones
 * Version 0.1
 * Copyright (c) 2004 Joseph Battaglia <sephail@sephail.net>
 */

#include <fcntl.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <linux/ioctl.h>
#include <linux/soundcard.h>
#include <linux/stat.h>
#include <linux/types.h>
#include <linux/input.h>
#include <unistd.h>

#define BITS 8
#define BUF_SIZE 4096
#define CHANNELS 1
#define DEVICE "/dev/dsp"
#define RATE 8000
#define VERSION "0.1"


char *device;
int bits, channels, rate, silent = 0;

int bufpos = 0, sound_fd;
unsigned char audio_buffer[BUF_SIZE];


void write_buffer(void) {

    if(bufpos != 0) {

	if(write(sound_fd, audio_buffer, bufpos) == -1) {
	    perror("write()");
	    exit(1);
	} else {
	    fsync(sound_fd);
	}

	bufpos = 0;

    }

}


void add_to_buffer(int val) {

    int i;

    if(bufpos >= BUF_SIZE - 4) {
	write_buffer();
    }

    for(i = 0; i < channels; i++) {

	if(bits == 8) {
	    audio_buffer[bufpos++] = 128 + (val >> 8);
	}

	if(bits == 16) {
	    audio_buffer[bufpos++] = val & 0xff;
	    audio_buffer[bufpos++] = (val >> 8) & 0xff;
	}

    }

}


void single_tone(int freq, int msec) {

    double add, c;
    int length, val;

    add = (double)freq / rate;
    length = (msec * rate) / 1000;

    while(--length >= 0) {

	val = (int)(sin(c * 2 * M_PI) * 16383);

	add_to_buffer(val);

	c += add;

    }

    write_buffer();

}


void dual_tone(int freq1, int freq2, int msec) {

    double add1, add2, c1, c2;
    int length, val, val1, val2;

    add1 = (double)freq1 / rate;
    add2 = (double)freq2 / rate;
    length = (msec * rate) / 1000;

    while(--length >= 0) {

	val1 = (int)(sin(c1 * 2 * M_PI) * 16383);
	val2 = (int)(sin(c2 * 2 * M_PI) * 16383);

	val = val1 + val2;

	add_to_buffer(val);

	c1 += add1;
	c2 += add2;

    }

    write_buffer();

}


void touch_tone(char tone, int msec) {

    switch(tone) {
	case '0':
	    dual_tone(941, 1336, msec);
	    break;
	case '1':
	    dual_tone(697, 1209, msec);
	    break;
	case '2':
	    dual_tone(697, 1336, msec);
	    break;
	case '3':
	    dual_tone(697, 1477, msec);
	    break;
	case '4':
	    dual_tone(770, 1209, msec);
	    break;
	case '5':
	    dual_tone(770, 1336, msec);
	    break;
	case '6':
	    dual_tone(770, 1477, msec);
	    break;
	case '7':
	    dual_tone(852, 1209, msec);
	    break;
	case '8':
	    dual_tone(852, 1336, msec);
	    break;
	case '9':
	    dual_tone(852, 1477, msec);
	    break;
	case '*':
	    dual_tone(941, 1209, msec);
	    break;
	case '#':
	    dual_tone(941, 1477, msec);
	    break;
	case 'A':
	    dual_tone(697, 1633, msec);
	    break;
	case 'B':
	    dual_tone(770, 1633, msec);
	    break;
	case 'C':
	    dual_tone(852, 1633, msec);
	    break;
	case 'D':
	    dual_tone(941, 1633, msec);
	    break;
	case 'R':
	    dual_tone(440, 480, msec);
	    break;
	case 'S':
	    dual_tone(480, 620, msec);
	    break;
	case 'T':
	    dual_tone(350, 440, msec);
	    break;
	case ',':
	    dual_tone(0, 0, msec);
	    break;
    }

}


void print_version(FILE *stream) {

    fprintf(stream, "tonegen - Generate single, dual, or Touch Tone tones\n");
    fprintf(stream, "Version %s\n", VERSION);
    fprintf(stream, "Copyright (c) 2004 Joseph Battaglia\n");

}


void print_help(FILE *stream, char *exec) {

    print_version(stream);

    fprintf(stream, " Usage %s [OPTIONS]\n", exec);
    fprintf(stream, "  -a   Specify a string of Touch Tone numbers\n");
    fprintf(stream, "  -b   Specify number of bits (default %d)\n", bits);
    fprintf(stream, "  -c   Specify number of channels (default %d)\n", channels);
    fprintf(stream, "  -d   Specify sound card device (default %s)\n", device);
    fprintf(stream, "  -f   Specify frequencies (one, two, or Touch Tone)\n");
    fprintf(stream, "         eg. -f 2600 (or) -f 1100,1700 (or) -f T1 \n");
    fprintf(stream, "         Special T tones: R: ring  S: busy  T: dial\n");
    fprintf(stream, "  -h   Show help and exit\n");
    fprintf(stream, "  -l   Specify length of tone (in miliseconds)\n");
    fprintf(stream, "  -m   Match tonegen settings to sound card (closest supported match)\n");
    fprintf(stream, "  -r   Specify sample rate (default %d)\n", rate);
    fprintf(stream, "  -s   Silent\n");
    fprintf(stream, "  -v   Show version and exit\n");

}


int main(int argc, char *argv[]) {
    int listen_to_touch = 0;
    char *touch_device = 0;
    char tt = -1;
    char *tts = NULL;
    int ch, freq1 = 0, freq2 = 0, i, length = 1000, match = 0;
    int s_bits, s_channels, s_rate;
    extern char *optarg;

    bits = BITS;
    channels = CHANNELS;
    rate = RATE;

    if((device = malloc(strlen(DEVICE) + 1)) == NULL) {
	perror("malloc()");
	exit(1);
    }

    strcpy(device, DEVICE);

    while((ch = getopt(argc, argv, "t:a:b:c:d:f:hl:mr:sv")) != -1) {
	switch(ch) {
	    case 't':
		listen_to_touch = 1;
		if((touch_device = malloc(strlen(optarg) + 1)) == NULL) {
		    perror("malloc()");
		    exit(1);
		}
		strcpy(touch_device, optarg);
		break;
	    case 'a':
		if((tts = malloc(strlen(optarg) + 1)) == NULL) {
		    perror("malloc()");
		    exit(1);
		}
		strcpy(tts, optarg);
		break;
	    case 'b':
		bits = atoi(optarg);
		if(bits != 8 && bits != 16) {
		    fprintf(stderr, "-b argument must be either 8 or 16\n");
		    exit(1);
		}
		break;
	    case 'c':
		channels = atoi(optarg);
		if(channels != 1 && channels != 2) {
		    fprintf(stderr, "-c argument must be either 1 or 2\n");
		    exit(1);
		}
		break;
	    case 'd':
		if((device = realloc(device, strlen(optarg) + 1)) == NULL) {
		    perror("realloc()");
		    exit(1);
		}
		strcpy(device, optarg);
		break;
	    case 'f':
		if(optarg[0] == 'T') {
		    tt = optarg[1];
		}
		else {
		    if(strchr(optarg, ',') == NULL) {
			if((freq1 = atoi(optarg)) < 0) {
			    fprintf(stderr, "Invalid frequency\n");
			    exit(1);
			}
		    }
		    else {
			if((freq1 = atoi(strtok(optarg, ","))) < 0) {
			    fprintf(stderr, "Invalid frequency\n");
			    exit(1);
			}
			if((freq2 = atoi(strtok(NULL, ","))) < 0) {
			    fprintf(stderr, "Invalid frequency\n");
			    exit(1);
			}
		    }
		}
		break;
	    case 'h':
		print_help(stdout, argv[0]);
		return(0);
		break;
	    case 'l':
		length = atoi(optarg);
		if(rate <= 0) {
		    fprintf(stderr, "Invalid length argument\n");
		    exit(1);
		}
		break;
	    case 'm':
		match = 1;
		break;
	    case 'r':
		rate = atoi(optarg);
		if(rate <= 0 && rate > 65535) {
		    fprintf(stderr, "Invalid sample rate\n");
		    exit(1);
		}
		break;
	    case 's':
		silent = 1;
		break;
	    case 'v':
		print_version(stdout);
		return(0);
		break;
	    default:
		break;
	}
}

i = 0;
if(freq1) { i++; }
if(tt != -1) { i++; }
if(tts != NULL) { i++; }
/*
if(i > 1) {
    fprintf(stderr, "You may only specify one type of tone generation\n\n");
    print_help(stderr, argv[0]);
    exit(1);
}
*/
if(i < 1) {
    fprintf(stderr, "Please specify a type of tone generation\n");
    print_help(stderr, argv[0]);
    exit(1);
}

if((sound_fd = open(device, O_WRONLY)) == -1) {
    perror("open()");
    exit(1);
}

if(match) {
    if(ioctl(sound_fd, SOUND_PCM_WRITE_BITS, &bits) == -1) {
	perror("ioctl()");
	exit(1);
    }
    if(ioctl(sound_fd, SOUND_PCM_WRITE_CHANNELS, &channels) == -1) {
	perror("ioctl()");
	exit(1);
    }
    if(ioctl(sound_fd, SOUND_PCM_WRITE_RATE, &rate) == -1) {
	perror("ioctl()");
	exit(1);
    }
}

if(ioctl(sound_fd, SOUND_PCM_READ_BITS, &s_bits) == -1) {
    perror("ioctl()");
    exit(1);
}
if(ioctl(sound_fd, SOUND_PCM_READ_CHANNELS, &s_channels) == -1) {
    perror("ioctl()");
    exit(1);
}
if(ioctl(sound_fd, SOUND_PCM_READ_RATE, &s_rate) == -1) {
    perror("ioctl()");
    exit(1);
}

if(match) {
    bits = s_bits;
    channels = s_channels;
    rate = s_rate;
}

if(!silent) {
    print_version(stdout);
    printf("\n");
    printf("Device: %s\n", device);
    printf("\n");
    printf("Sound Card Settings\n");
    printf("-------------------\n");
    printf("Bits: %d\n", s_bits);
    printf("Channels: %d\n", s_channels);
    printf("Rate: %dhz\n", s_rate);
    printf("\n");
    printf("tonegen Settings\n");
    printf("-------------------\n");
    printf("Bits: %d\n", bits);
    printf("Channels: %d\n", channels);
    printf("Rate: %dhz\n", rate);
}

if(!freq1 && !freq2) {
    if(tts != NULL) {
	for(i = 0; i < strlen(tts); i++) {
	    touch_tone(tts[i], length);
	}
    }
    else {
	touch_tone(tt, length);
    }
}
else {
    if(!freq2) {
	single_tone(freq1, length);
    }
    else {
	dual_tone(freq1, freq2, length);
    }
}

if (listen_to_touch) {
    int i, fd;
    struct input_event ev[64];
    if ((fd = open(touch_device, O_RDONLY)) < 0) {
        perror("Couldn't open input device");
        return 1;
    }

    while (1) {
        size_t rb = read(fd, ev, sizeof(ev));

        if (rb < (int) sizeof(struct input_event)) {
            perror("short read");
            return 1;
        }

        for (i = 0; i < (int) (rb / sizeof(struct input_event)); i++) {
	    if (ev[i].type == 3 && ev[i].code == 24 && ev[i].value == 0) {
		printf("meep!\n");
		if(!freq1 && !freq2) {
		    if(tts != NULL) {
			for(i = 0; i < strlen(tts); i++) {
			    touch_tone(tts[i], length);
			}
		    }
		    else {
			touch_tone(tt, length);
		    }
		}
		else {
		    if(!freq2) {
			single_tone(freq1, length);
		    }
		    else {
			dual_tone(freq1, freq2, length);
		    }
		}
	    }
        }
    }
    
}

close(sound_fd);

return(0);

}



