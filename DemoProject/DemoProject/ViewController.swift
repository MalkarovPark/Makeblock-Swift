//
//  ViewController.swift
//  DemoProject
//
//  Created by Wang Yu on 6/7/16.
//  Copyright © 2016 Makeblock. All rights reserved.
//

import UIKit
import Makeblock

var connection = BluetoothConnection()
var mBot = MBot(connection: connection)

class BluetoothDeviceTableViewCell: UITableViewCell {
    @IBOutlet weak var nameLabel: UILabel!

}

class MainViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var deviceTableView: UITableView!
    var deviceList: [BluetoothDevice] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        deviceTableView.dataSource = self;
        deviceTableView.delegate = self;
        connection.onAvailableDevicesChanged = { devices in
            if let bleDevices = devices as? [BluetoothDevice] {
                self.deviceList = bleDevices
                self.deviceTableView.reloadData()
            }
        }
        
        connection.onConnect = {
            self.performSegue(withIdentifier: "showDetails", sender: nil)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return deviceList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let deviceCell = deviceTableView.dequeueReusableCell(withIdentifier: "deviceTableView", for: indexPath) as! BluetoothDeviceTableViewCell
        let device = deviceList[indexPath.row]
        deviceCell.nameLabel.text = "\(device.name) (\(device.distance))"
        return deviceCell
        
        
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let device = deviceList[indexPath.row]
        connection.connect(device: device)
    }
}

