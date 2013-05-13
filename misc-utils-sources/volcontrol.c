/*
 * Huan Truong's volume control for the Chumby
 * Sample program that listens to the rotary encoder and plays sound.
 * 
 * Based on keytable.c by Mauro Carvalho Chehab
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 2 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <pthread.h>

#include <linux/input.h>

#include <string.h>
#include <linux/input.h>
#include <sys/ioctl.h>

#define KEY_RELEASE 0
#define KEY_PRESS 1
#define KEY_KEEPING_PRESSED 2

void * volcontroller_loop(void * arg)
{
  int *vol_flag;
  while (1) {
      vol_flag = (int *)(arg);
      if (*vol_flag != 0) {
	    // save the framebuffer before overlaying stuff on it
	    int ret;
	    char vol_buffer [5];
	    char cmd_buffer [100];
	    //ret = system("/usr/bin/imgtool --mode=cap /tmp/tmpfb.png");

	    snprintf(vol_buffer, 4,"%d", *vol_flag);

	    system("/psp/utils/beep -f1500 -l5 -s");

	    fprintf(stderr,"Calling %s\n",cmd_buffer);
	    ret = system(cmd_buffer);
	    //clear the flag
	    *vol_flag = 0;
    } else {
	usleep(500000);
    }
  }
}

int main (int argc, char *argv[]) {
    int i, fd;
    int rotary_flag; // being 0 - flag clear, or any int number for direction
    
    struct input_event ev[64];

    if (argc != 2) {
        fprintf(stderr, "usage: %s event-device (/dev/input/eventX)\n", argv[0]);
        return 1;
    }

    if ((fd = open(argv[1], O_RDONLY)) < 0) {
        perror("Couldn't open input device");
        return 1;
    }

    pthread_t volcontroller_thread;

    if (pthread_create (&volcontroller_thread, NULL, volcontroller_loop, (void *)(&rotary_flag)) )
    { printf("Can't create thread!"); abort(); }


    while (1) {
        size_t rb = read(fd, ev, sizeof(ev));

        if (rb < (int) sizeof(struct input_event)) {
            perror("short read");
            return 1;
        }

        for (i = 0; i < (int) (rb / sizeof(struct input_event)); i++) {
	    if (ev[i].type == 2 && ev[i].code == 8) {
		rotary_flag = ev[i].value;
	    }
        }
    }

    if (pthread_join (volcontroller_thread, NULL) ) {
	printf("Can't join!"); abort();
    }
        
    return 0;
}

