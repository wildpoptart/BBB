/*
 * Print GPIO_GET_CHIPINFO_IOCTL as compiled for *this* ABI.
 * Build inside the 32-bit container:
 *   gcc -o chipinfo_guest_cmd chipinfo_guest_cmd.c && ./chipinfo_guest_cmd
 * Put that hex into TARGET_GPIO_GET_CHIPINFO_IOCTL if it is not 0x8044b401.
 */
#include <stdio.h>
#include <linux/gpio.h>

int main(void)
{
    printf("sizeof(struct gpiochip_info) = %zu\n", sizeof(struct gpiochip_info));
    printf("GPIO_GET_CHIPINFO_IOCTL      = 0x%08x\n", GPIO_GET_CHIPINFO_IOCTL);
    return 0;
}
