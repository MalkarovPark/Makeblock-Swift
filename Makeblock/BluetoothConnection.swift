//
//  BluetoothConnection.swift
//  Makeblock
//
//  Created by Wang Yu on 6/6/16.
//  Copyright © 2016 Makeblock. All rights reserved.
//

import Foundation
import CoreBluetooth

/// An bluetooth device
public class BluetoothDevice: Device{
    var peripheral: CBPeripheral?
    var RSSI: NSNumber?

    func distanceByRSSI() -> Float{
        if let rssi = RSSI {
            return powf(10.0,((abs(rssi.floatValue)-50.0)/50.0))*0.7
        }
        return -1.0
    }

    /**
     Create a device using a CBPeripheral 
     Normally you don't need to init a BluetoothDevice by yourself
     
     - parameter peri: the peripheral instance
     
     - returns: nil
     */
    public init(peri: CBPeripheral) {
        super.init()
        peripheral = peri
    }
    
    public override init () {
        super.init()
    }
}

/// The bluetooth connection
public class BluetoothConnection: NSObject, Connection, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // Bluetooth Module Characteristics
    let readWriteServiceUUID = "FFE1"
    let readNotifyCharacteristicUUID = "FFE2"
    let writeCharacteristicUUID = "FFE3"
    /// the maximum length of the package that can be send
    let notifyMTU = 20      // maximum 20 bytes in a single ble package
    
    // CoreBluetooth related
    var centralManager: CBCentralManager?
    var peripherals: [CBPeripheral] = []
    var activePeripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    var notifyReady = false
    
    // Connection related
    var deviceList: [BluetoothDevice] = []
    public var onConnect: (() -> Void)?
    public var onDisconnect: (() -> Void)?
    public var onReceive: ((NSData) -> Void)?
    public var onAvailableDevicesChanged: (([Device]) -> Void)?
    var isConnectingDefaultDevice = false
    
    override public init ()
    {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    // Connection Methods
    /// Start scanning Bluetooth devices
    public func startDiscovery() {
        centralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: 0])
    }
    
    /// Stop scanning Bluetooth devices
    public func stopDiscovery() {
        centralManager?.stopScan()
    }
    
    /// Stop and start scanning Bluetooth devices
    func resetDiscovery() {
        stopDiscovery()
        startDiscovery()
    }
    
    /// Connect to a bluetooth device
    public func connect(device: Device)
    {
        if let bluetoothDevice = device as? BluetoothDevice
        {
            centralManager?.connect(bluetoothDevice.peripheral!, options: nil)
            stopDiscovery()
        }
    }
    
    /// TODO: Connect to the nearest bluetooth device after 5 seconds
    public func connectDefaultDevice()
    {
        isConnectingDefaultDevice = true
        startDiscovery()
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5)
        {
            // connect to the nearest devices after 5 seconds
            if !self.deviceList.isEmpty
            {
                self.connect(device: self.deviceList[0])
            }
        }
    }
    
    public func disconnect() {
        if let peripheral = activePeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
            resetDiscovery()
        }
    }
    
    public func send(data: NSData) {
        if let peripheral = activePeripheral {
            if peripheral.state == .connected {
                if let characteristic = writeCharacteristic {
                    var sendIndex = 0
                    while true {
                        var amountToSend = data.length - sendIndex
                        if amountToSend > notifyMTU {
                            amountToSend = notifyMTU
                        }
                        if amountToSend <= 0 {
                            return;
                        }
                        let dataChunk = NSData(bytes: data.bytes+sendIndex, length: amountToSend)
                        peripheral.writeValue(dataChunk as Data, for: characteristic, type: .withoutResponse)
                        sendIndex += amountToSend
                    }
                }
            }
        }
    }
    
    // CoreBluetooth Methods
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if centralManager == central {
            if central.state == .poweredOn {
                startDiscovery()
            } else {
                resetDiscovery()
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber)
    {
        guard centralManager == central else { return }
        if !peripherals.contains(peripheral)
        {
            if let name = peripheral.name, name.hasPrefix("Makeblock")
            {
                peripherals.append(peripheral)
                print ("Adding peripherals \(peripherals)")
                let device = BluetoothDevice(peri: peripheral)
                device.RSSI = RSSI
                device.distance = device.distanceByRSSI()
                device.name = peripheral.name ?? "Unknown"
                
                deviceList.append(device)
                
                // Отсортировать устройства в зависимости от их расстояния для пользователя
                if deviceList.count > 1
                {
                    deviceList.sort { $0.distanceByRSSI() < $1.distanceByRSSI() }
                }
                
                if let callback = onAvailableDevicesChanged
                {
                    callback(deviceList)
                }
            }
        }
    }
    
    /// Connected says central manager
    public func centralManager(central: CBCentralManager, didConnectPeripheral peripheral: CBPeripheral) {
        if centralManager!.isEqual(central) {
            if !peripherals.contains(peripheral) {
                peripherals.append(peripheral)
                print("added undiscovered peripheral \(peripheral.identifier.uuidString)")
            }
            
            activePeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([CBUUID(string: readWriteServiceUUID)])
        }
    }
    
    /// TODO: Fail to connect says central manager
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?)
    {
        print("failed to connect peripheral")
    }
    
    /// Disconnected says central manager
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?)
    {
        if let callback = onDisconnect
        {
            callback()
        }
    }
    
    /// Service discovered
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?)
    {
        if peripheral == activePeripheral
        {
            if let services = peripheral.services
            {
                for service in services
                {
                    print("discovered service \(service.uuid)")
                    if service.uuid == CBUUID(string: readWriteServiceUUID)
                    {
                        peripheral.discoverCharacteristics(nil, for: service)
                    }
                }
            }
        }
    }
    
    /// If both write characteristic and notify is setup, call "onConnected" callback
    func checkAndNotifyIfConnected() {
        if notifyReady && writeCharacteristic != nil {
            if let callback = onConnect {
                callback()
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?)
    {
        if peripheral == activePeripheral
        {
            if let characteristics = service.characteristics
            {
                for characteristic in characteristics
                {
                    if characteristic.uuid == CBUUID(string: writeCharacteristicUUID)
                    {
                        writeCharacteristic = characteristic
                        checkAndNotifyIfConnected()
                    }
                    else if characteristic.uuid == CBUUID(string: readNotifyCharacteristicUUID)
                    {
                        peripheral.setNotifyValue(true, for: characteristic)
                        notifyReady = true
                        checkAndNotifyIfConnected()
                    }
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        if error == nil
        {
            if peripheral == activePeripheral
            {
                if let callback = onReceive, characteristic.uuid == CBUUID(string: readNotifyCharacteristicUUID)
                {
                    if let value = characteristic.value
                    {
                        callback(value as NSData)
                    }
                }
            }
        }
    }
}
