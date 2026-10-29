/*
 * Minimal libgpiod 1.x sample for the qemu -M virt Debian armhf guest.
 *
 *   sudo modprobe gpio-mockup gpio_mockup_ranges=-1,32
 *   sudo apt install libgpiod-dev gpiod
 *   gcc guest-blink.c -lgpiod -o guest-blink
 *   ./guest-blink
 */
#include <gpiod.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(void)
{
    struct gpiod_chip *chip;
    struct gpiod_line *line;
    int i;

    chip = gpiod_chip_open_by_name("gpiochip0");
    if (!chip) {
        perror("gpiod_chip_open_by_name");
        return 1;
    }

    line = gpiod_chip_get_line(chip, 0);
    if (!line) {
        perror("gpiod_chip_get_line");
        gpiod_chip_close(chip);
        return 1;
    }

    if (gpiod_line_request_output(line, "guest-blink", 0) < 0) {
        perror("gpiod_line_request_output");
        gpiod_chip_close(chip);
        return 1;
    }

    for (i = 0; i < 5; i++) {
        gpiod_line_set_value(line, 1);
        printf("line0 = 1\n");
        sleep(1);
        gpiod_line_set_value(line, 0);
        printf("line0 = 0\n");
        sleep(1);
    }

    gpiod_chip_close(chip);
    return 0;
}
