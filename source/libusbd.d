/*
 * Public libusbd header file
 * Copyright © 2014 Olivier Pisano <olivier.pisano@laposte.net>
 *
 * For more information, please visit: http://libusbx.org
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the 
 License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

module libusbd;

import core.atomic;
import core.stdc.stdlib: malloc, free;
import std.conv;
import libusbc;

/**
 * This class is used for signaling libusb related errors.
 */
class USBException : Exception
{
public:
    this(string msg)
    {
        super(msg);
    }
}

/**
 * Structure representing a libusbx session.
 *
 * The concept of individual libusbx sessions allows for your program to 
 * use two libraries (or dynamically load two modules) which both 
 * independently use libusb. This will prevent interference between the 
 * individual libusbx users - for example setDebug() will not 
 * affect the other user of the library
 */
struct Context
{
private:
    libusb_context* ctx;

public:

    /**
     * Initializes a libusb session.
     */
    void init()
    in
    {
        assert (ctx is null);
    }
    out
    {
        assert (ctx !is null);
    }
    body
    {
        auto ret = libusb_init(&ctx);
        if (ret != 0)
        {
            throw new USBException("Cannot initialize libusb");
        }
    }

    /**
     * Set log message verbosity.
     *
     * The default level is LIBUSB_LOG_LEVEL_NONE, which means no messages 
     * are ever printed. If you choose to increase the message verbosity 
     * level, ensure that your application does not close the 
     * stdout/stderr file descriptors.
     * 
     * You are advised to use level LIBUSB_LOG_LEVEL_WARNING. libusbx is 
     * conservative with its message logging and most of the time, will 
     * only log messages that explain error conditions and other oddities. 
     * This will help you debug your software.
     * 
     * If the LIBUSB_DEBUG environment variable was set when libusbx was 
     * initialized, this function does nothing: the message verbosity is 
     * fixed to the value in the environment variable.
     * 
     * If libusbx was compiled without any message logging, this function 
     * does nothing: you'll never get any messages.
     * 
     * If libusbx was compiled with verbose debug message logging, this 
     * function does nothing: you'll always get messages from all levels.
     */
    void setDebug(libusb_log_level lvl)
    {
        libusb_set_debug(ctx, lvl);
    }

    /** Releases libusb session */
    ~this()
    {
        libusb_exit(ctx);
    }
    
    /**
      * Convenience function for finding a device with a particular 
      * idVendor/idProduct combination.
      * 
      * This function is intended for those scenarios where you are using 
      * libusbx to knock up a quick test application - it allows you to avoid 
      * calling Context.devices().
      * 
      * This function has limitations and is hence not intended for use in real 
      * applications: if multiple devices have the same IDs it will only give 
      * you the first one, etc.
      */
    DeviceHandle open(ushort vendor_id, ushort product_id)
    {
        libusb_device_handle* h = libusb_open_device_with_vid_pid(ctx,
                                                                  vendor_id, 
                                                                  product_id);
        if (h is null)
        {
            throw new USBException("libusb_open_with_vid_pid failed");
        }
        
        DeviceHandle dh = { h };
        return dh;
    }
    
    /**
     * Returns an input range of Device objects present on the system.
     */
    auto devices()
    {
        /**
         * Our input range structure
         */
        struct DeviceList
        {
        private:
            libusb_device** m_devices;
            ptrdiff_t m_count;
            ptrdiff_t m_index;
            
        public:
            
            ~this()
            {
                libusb_free_device_list(m_devices, 1);
            }
            
            @property bool empty() const
            {
                return m_index >= m_count;
            }
            
            @property Device front()
            {
                Device d;
                d.dev = m_devices[m_index];
                libusb_ref_device(d.dev);
                return d;
            }
            
            void popFront()
            {
                m_index++;
            }
        }
        
        libusb_device** devices_;
        auto n = libusb_get_device_list(ctx, &devices_);
        
        // Check errors
        if (n < 0)
        {
            auto err = cast(libusb_error) n;
            auto msg = to!string(libusb_strerror(err));
            throw new USBException(msg);
        }
        
        DeviceList dl = { devices_, n, 0 };        
        return dl;
    }
    /**
     * Get an endpoints superspeed endpoint companion descriptor (if any)
     */
    auto getSSEndpointCompanionDescriptor(ref const EndpointDescriptor ed)
    {
        libusb_ss_endpoint_companion_descriptor* desc;
        auto r = libusb_get_ss_endpoint_companion_descriptor(ctx, &ed, &desc);
        if (r != 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return SSEndpointCompanionDescriptor(desc);
    }
    
    /**
     * Get an USB 2.0 Extension descriptor. 
     */
    auto getUSB20ExtensionDescriptor(ref BOSDevCapabilityDescriptor devcap)
    {
        libusb_usb_2_0_extension_descriptor* desc;
        auto r = libusb_get_usb_2_0_extension_descriptor(ctx, &devcap, &desc);
        if (r != 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return USB20ExtensionDescriptor(desc);
    }
    
    /**
     * Get a SuperSpeed USB Device Capability descriptor. 
     */
    auto getSSUSBDeviceCapabilityDescriptor(ref BOSDevCapabilityDescriptor devcap)
    {
        libusb_ss_usb_device_capability_descriptor* desc;
        auto r = libusb_get_ss_usb_device_capability_descriptor(ctx,
                                                                &devcap,
                                                                &desc);
        if (r != 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return SSUSBDeviceCapabilityDescriptor(desc);
    }
    
    /**
     * Get a Container ID descriptor. 
     */
    auto getContainerIDDescriptor(ref BOSDevCapabilityDescriptor devcap)
    {
        libusb_container_id_descriptor* desc;
        auto r = libusb_get_container_id_descriptor(ctx, &devcap, &desc);
        if (r != 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return ContainerIDDescriptor(desc);
    }
}

/** 
 * Helper function that returns an initialized Context.
 */
auto context()
{
    Context c;
    c.init();

    return c;
}

/**
 * Structure representing a USB device detected on the system.
 */
struct Device
{
private:
    libusb_device* dev;
public:
     this(this)
     {
         libusb_ref_device(dev);
     }
     
     ~this()
     {
         libusb_unref_device(dev);
     }
     
     void opAssign(ref Device other)
     {
         if (dev !is other.dev)
         {
             if (dev !is null)
             {
                 libusb_unref_device(dev);
             }
             dev = other.dev;
             libusb_ref_device(dev);
         }
     }
     
     void opAssign(Device other)
     {
         if (dev !is other.dev)
         {
             if (dev !is null)
             {
                 libusb_unref_device(dev);
             }
             dev = other.dev;
         }
     }
     
     /**
      * Number of the bus that a device is connected to. 
      */
     @property ubyte busNumber() 
     {
         return libusb_get_bus_number(dev);
     }
     
     /**
      * Number of the port that a device is connected to. 
      */
     @property ubyte portNumber()
     {
         return libusb_get_port_number(dev);
     }
     
     /**
      * Get the the parent from the specified device. 
      */
     @property Device parent()
     {
         auto d = libusb_get_parent(dev);
         return createDevice(d);
     }
     
     /**
      * Get the address of the device on the bus it is connected to. 
      */
     @property ubyte address()
     {
         return libusb_get_device_address(dev);
     }
     
     /**
      * Get the negotiated connection speed for a device. 
      */
     @property libusb_speed speed()
     {
         return cast(libusb_speed)libusb_get_device_speed(dev);
     }
     
     /**
      * Convenience function to retrieve the wMaxPacketSize value for a
      * particular endpoint in the active device configuration. 
      * 
      * 
      * This function was originally intended to be of assistance when setting 
      * up isochronous transfers, but a design mistake resulted in this 
      * function instead. It simply returns the wMaxPacketSize value without 
      * considering its contents. If you're dealing with isochronous transfers, 
      * you probably want getMaxISOPacketSize() instead.
      */
     int getMaxPacketSize(ubyte endpoint)
     {
         auto r = libusb_get_max_packet_size(dev, endpoint);
         if (r < 0)
         {
             throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
         }
         
         return r;
     }
     
     /**
      * Calculate the maximum packet size which a specific endpoint is capable 
      * is sending or receiving in the duration of 1 microframe.
      *
      * Only the active configuration is examined. The calculation is based on 
      * the wMaxPacketSize field in the endpoint descriptor as described in 
      * section 9.6.6 in the USB 2.0 specifications.
      *
      * If acting on an isochronous or interrupt endpoint, this function will 
      * multiply the value found in bits 0:10 by the number of transactions per 
      * microframe (determined by bits 11:12). Otherwise, this function just 
      * returns the numeric value found in bits 0:10.
      *
      * This function is useful for setting up isochronous transfers, for 
      * example you might pass the return value from this function to 
      * libusb_set_iso_packet_lengths() in order to set the length field of 
      * every isochronous packet in a transfer.
      */
     int getMaxISOPacketSize(ubyte endpoint)
     {
         auto r = libusb_get_max_iso_packet_size(dev, endpoint);
         if (r < 0)
         {
             throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
         }
         
         return r;
     }
     
     /**
      * Open a device and obtain a device handle.
      *
      * A handle allows you to perform I/O on the device in question.
      */
     DeviceHandle open() 
     {
         libusb_device_handle* h;
         auto r = libusb_open(dev, &h);
         if (r < 0)
         {
             throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
         }
         
         DeviceHandle dh = { h };
         return dh;
     }
     
     /**
      * Get the USB configuration descriptor for the currently active 
      * configuration.
      *
      * This is a non-blocking function which does not involve any requests 
      * being sent to the device.
      */
     ConfigDescriptor getActiveConfigDescriptor()
     {
         libusb_config_descriptor* cd;
         auto r = libusb_get_active_config_descriptor(dev, &cd);
         if (r < 0)
         {
             throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
         }
         
         auto confDesc = ConfigDescriptor(cd);
         return confDesc;
     }
     
     /**
      * Get a USB configuration descriptor based on its index.
      *
      * This is a non-blocking function which does not involve any requests 
      * being sent to the device.
      */
     ConfigDescriptor getConfigDescriptor(ubyte index)
     {
         libusb_config_descriptor* cd;
         auto r = libusb_get_config_descriptor(dev, index, &cd);
         if (r < 0)
         {
             throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
         }
         
         auto confDesc = ConfigDescriptor(cd);
         return confDesc;
     }
     
     /**
      * Get a USB configuration descriptor with a specific bConfigurationValue.
      *
      * This is a non-blocking function which does not involve any requests 
      * being sent to the device.
      */
     ConfigDescriptor getConfigDescriptorByValue(ubyte configurationValue)
     {
         libusb_config_descriptor* cd;
         auto r = libusb_get_config_descriptor_by_value(dev, 
                    configurationValue,
                    &cd);
         if (r < 0)
         {
             throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
         }
         
         auto confDesc = ConfigDescriptor(cd);
         return confDesc;
     }
     
     
}

private Device createDevice(libusb_device* dev)
{
    Device d;
    d.dev = dev;
    libusb_ref_device(dev);
    return d;
}

/**
 * Structure representing a handle on a USB device. 
 */
struct DeviceHandle
{
    private libusb_device_handle* handle;
    
    ~this()
    {
        libusb_close(handle);
    }
    
    /**
     * Close a device handle. 
     */
    void close()
    {
        libusb_close(handle);
    }
    
    /**
     * Get the underlying device for a handle. 
     */
    @property Device device()
    {
        auto d = libusb_get_device(handle);
        return createDevice(d);
    }
    
    /**
     * Determine the bConfigurationValue of the currently active configuration.
     *
     * You could formulate your own control request to obtain this information, 
     * but this function has the advantage that it may be able to retrieve the 
     * information from operating system caches (no I/O involved).
     *
     * If the OS does not cache this information, then this function will block 
     * while a control transfer is submitted to retrieve the information.
     */
    @property int configuration()
    {
        int config;
        auto r = libusb_get_configuration(handle, &config);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return config;
    }
    
    /**
     * Set the active configuration for a device.
     * 
     * The operating system may or may not have already set an active 
     * configuration on the device. It is up to your application to ensure the 
     * correct configuration is selected before you attempt to claim interfaces 
     * and perform other operations.
     *
     * If you call this function on a device already configured with the 
     * selected configuration, then this function will act as a lightweight 
     * device reset: it will issue a SET_CONFIGURATION request using the 
     * current configuration, causing most USB-related device state to be 
     * reset (altsetting reset to zero, endpoint halts cleared, toggles reset).
     *
     * You cannot change/reset configuration if your application has claimed 
     * interfaces. It is advised to set the desired configuration before 
     * claiming interfaces.
     *
     * Alternatively you can call libusb_release_interface() first. Note if you 
     * do things this way you must ensure that auto_detach_kernel_driver for 
     * dev is 0, otherwise the kernel driver will be re-attached when you 
     * release the interface(s).
     * 
     * You cannot change/reset configuration if other applications or drivers 
     * have claimed interfaces.
     * 
     * A configuration value of -1 will put the device in unconfigured state. 
     * The USB specifications state that a configuration value of 0 does this, 
     * however buggy devices exist which actually have a configuration 0.
     * 
     * You should always use this function rather than formulating your own 
     * SET_CONFIGURATION control request. This is because the underlying 
     * operating system needs to know when such changes happen.
     */
    @property void configuration(int value)
    {
        auto r = libusb_set_configuration(handle, value);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Claim an interface on a given device handle.
     * 
     * You must claim the interface you wish to use before you can perform I/O 
     * on any of its endpoints.
     *
     * It is legal to attempt to claim an already-claimed interface, in which 
     * case libusbx just returns 0 without doing anything.
     *
     * If auto_detach_kernel_driver is set to 1 for dev, the kernel driver will 
     * be detached if necessary, on failure the detach error is returned.
     *
     * Claiming of interfaces is a purely logical operation; it does not cause 
     * any requests to be sent over the bus. Interface claiming is used to 
     * instruct the underlying operating system that your application wishes to 
     * take ownership of the interface.
     */
    void claimInterface(int interface_number)
    {
        auto r = libusb_claim_interface(handle, interface_number);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Release an interface previously claimed with claimInterface().
     * 
     * You should release all claimed interfaces before closing a device handle.
     * 
     * This is a blocking function. A SET_INTERFACE control request will be 
     * sent to the device, resetting interface state to the first alternate 
     * setting.
     * 
     * If auto_detach_kernel_driver is set to 1 for dev, the kernel driver will 
     * be re-attached after releasing the interface.
     */
    void releaseInterface(int interface_number)
    {
        auto r = libusb_release_interface(handle, interface_number);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Activate an alternate setting for an interface.
     *
     * The interface must have been previously claimed with claimInterface().
     *
     * You should always use this function rather than formulating your own 
     * SET_INTERFACE control request. This is because the underlying operating 
     * system needs to know when such changes happen.
     */
    void setInterfaceAltSetting(int interface_number, int alternate_setting)
    {
        auto r = libusb_set_interface_alt_setting(handle, interface_number, 
                                                  alternate_setting);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Clear the halt/stall condition for an endpoint.
     *
     * Endpoints with halt status are unable to receive or transmit data until 
     * the halt condition is stalled.
     *
     * You should cancel all pending transfers before attempting to clear the 
     * halt condition.
     */
    void clearHalt(ubyte endpoint)
    {
        auto r = libusb_clear_halt(handle, endpoint);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Perform a USB port reset to reinitialize a device.
     *
     * The system will attempt to restore the previous configuration and 
     * alternate settings after the reset has completed.
     *
     * If the reset fails, the descriptors change, or the previous state cannot 
     * be restored, the device will appear to be disconnected and reconnected. 
     * This means that the device handle is no longer valid (you should close 
     * it) and rediscover the device. A return code of LIBUSB_ERROR_NOT_FOUND 
     * indicates when this is the case.
     */
    void reset()
    {
        auto r = libusb_reset_device(handle);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Determine if a kernel driver is active on an interface.
     *
     * If a kernel driver is active, you cannot claim the interface, and 
     * libusbx will be unable to perform I/O.
     *
     * This functionality is not available on Windows.
     */
    bool isKernelDriverActive(int interface_number)
    {
        auto r = libusb_kernel_driver_active(handle, interface_number);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return (r == 1);
    }
    
    /**
     * Detach a kernel driver from an interface.
     *
     * If successful, you will then be able to claim the interface and perform 
     * I/O.
     *
     * This functionality is not available on Darwin or Windows.
     * 
     * Note that libusbx itself also talks to the device through a special 
     * kernel driver, if this driver is already attached to the device, this 
     * call will not detach it and return LIBUSB_ERROR_NOT_FOUND.
     */
    void detachKernelDriver(int interface_number)
    {
        auto r = libusb_detach_kernel_driver(handle, interface_number);
        if (r < 0) 
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Re-attach an interface's kernel driver, which was previously detached 
     * using libusb_detach_kernel_driver().
     *
     * This call is only effective on Linux and returns 
     * LIBUSB_ERROR_NOT_SUPPORTED on all other platforms.
     *
     * This functionality is not available on Darwin or Windows.
     */
    void attachKernelDriver(int interface_number)
    {
        auto r = libusb_attach_kernel_driver(handle, interface_number);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Enable/disable libusbx's automatic kernel driver detachment.
     * 
     * When this is enabled libusbx will automatically detach the kernel driver 
     * on an interface when claiming the interface, and attach it when 
     * releasing the interface.
     *
     * Automatic kernel driver detachment is disabled on newly opened device 
     * handles by default.
     * 
     * On platforms which do not have LIBUSB_CAP_SUPPORTS_DETACH_KERNEL_DRIVER 
     * this function will return LIBUSB_ERROR_NOT_SUPPORTED, and libusbx will 
     * continue as if this function was never called.
     */
    void setAutoDetachKernelDriver(bool enabled)
    {
        auto r = libusb_set_auto_detach_kernel_driver(handle, enabled);
        if (r < 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
    }
    
    /**
     * Get a Binary Object Store (BOS) descriptor. 
     * This is a BLOCKING function, which will send requests to the device.
     */
    auto getBOSDescriptor()
    {
        libusb_bos_descriptor* desc;
        auto r  = libusb_get_bos_descriptor(handle, &desc);
        if (r != 0)
        {
            throw new USBException(to!string(libusb_strerror(cast(libusb_error)r)));
        }
        
        return BOSDescriptor(desc);
    }
    
    
}

alias DeviceDescriptor = libusb_device_descriptor;
alias EndpointDescriptor = libusb_endpoint_descriptor;
alias BOSDevCapabilityDescriptor = libusb_bos_dev_capability_descriptor;



/**
 * Encapsulate a libusb decriptor structure in a refcounted D object.
 *
 * No manual call to libusb_free_xxx_descriptor() is needed, as it will 
 * be called automatically when the reference count reaches 0.
 * 
 * T is the original libusb descriptor struture.
 * destructor is the libusb function that frees this type of descriptor. 
 */
struct Descriptor(T, alias destructor)
{
private:

    /**
     * Internal structure storing our payload and its reference count.
     */
    struct Impl
    {
        T* desc;
        shared(uint) refcount;
    }
    
    Impl* m_pimpl;
    alias m_pimpl this;
    
    this(T* desc)
    {
        // Allocate memory to store an Impl object
        m_pimpl = cast(Impl*) malloc(Impl.sizeof);
        if (m_pimpl is null)
        {
            throw new USBException("malloc returned null");
        }
        m_pimpl.desc = desc;
        atomicStore(m_pimpl.refcount, 1);
    }
    
public:
    ~this()
    {
        if (m_pimpl is null)
        {
            return;
        }
        
        if (atomicOp!"-="(m_pimpl.refcount, 1) == 0)
        {
            destructor(m_pimpl.desc);
            m_pimpl.desc = null;
            free(m_pimpl);
            m_pimpl = null;
        }
    }
    
    this(this)
    {
        if (m_pimpl is null)
            return;
        
        atomicOp!"+="(m_pimpl.refcount, 1);
    }
}

// Generate refcounted Descriptor types

alias ConfigDescriptor = Descriptor!(libusb_config_descriptor, 
                                     libusb_free_config_descriptor);
alias SSEndpointCompanionDescriptor = 
    Descriptor!(libusb_ss_endpoint_companion_descriptor,
                libusb_free_ss_endpoint_companion_descriptor);

alias BOSDescriptor = Descriptor!(libusb_bos_descriptor, 
                                  libusb_free_bos_descriptor);

alias USB20ExtensionDescriptor = 
                                Descriptor!(libusb_usb_2_0_extension_descriptor,
                                      libusb_free_usb_2_0_extension_descriptor);

alias SSUSBDeviceCapabilityDescriptor = 
                         Descriptor!(libusb_ss_usb_device_capability_descriptor,
                               libusb_free_ss_usb_device_capability_descriptor);
                         
alias ContainerIDDescriptor = Descriptor!(libusb_container_id_descriptor,
                                          libusb_free_container_id_descriptor);


// Hotplug


