//
//  HistoryTableViewController.swift
//  WhereTo
//
//  Created by Shannon Draeker on 6/23/20.
//  Copyright © 2020 Shannon Draeker. All rights reserved.
//

import UIKit

class HistoryTableViewController: UITableViewController {

    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Load the data if it hasn't been loaded already
        loadData()
        
        // Set up the tableview cells
        tableView.register(UINib(nibName: "RestaurantTableViewCell", bundle: nil), forCellReuseIdentifier: "restaurantCell")
        
        // Set up the observer to listen for changes in the data
        NotificationCenter.default.addObserver(self, selector: #selector(refreshData), name: updateHistoryList, object: nil)
        
        // Set up the observer to listen for notifications telling any view to display an alert
        setUpNotificationObservers()
    }
    
    // MARK: - Respond to Notifications
    
    @objc func refreshData() {
        print("got here to \(#function)")
        DispatchQueue.main.async { self.tableView.reloadData() }
    }
    
    // MARK: - Helper Methods
    
    func loadData() {
        if RestaurantController.shared.previousRestaurants == nil {
            RestaurantController.shared.fetchPreviousRestaurants { [weak self] (result) in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        // Reload the tableview
                        self?.tableView.reloadData()
                    case .failure(let error):
                        // Print and display the error
                        print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                        self?.presentErrorAlert(error)
                    }
                }
            }
        }
    }

    // MARK: - TableView Methods

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return RestaurantController.shared.previousRestaurants?.count ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "restaurantCell", for: indexPath) as? RestaurantTableViewCell else { return UITableViewCell() }

        guard let restaurant = RestaurantController.shared.previousRestaurants?[indexPath.row] else { return cell }
        cell.restaurant = restaurant
        cell.delegate = self
        
        if let currentUser = UserController.shared.currentUser {
            if currentUser.favoriteRestaurants.contains(restaurant.restaurantID) {
                cell.isFavoriteButton.isSelected = true
            }
        }
        return cell
    }
   
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // TODO: - enable swipe to delete
            // Delete the row from the data source
//            tableView.deleteRows(at: [indexPath], with: .fade)
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let restaurant = RestaurantController.shared.previousRestaurants?[indexPath.row] else { return }
        
        // Present an alert controller asking the user if they want to open the restaurant in maps
        presentChoiceAlert(title: "Open in Maps?", message: "", confirmText: "Open in Maps") {
            self.launchMapWith(restaurant: restaurant)
        }
    }
}

// MARK: - Extension:SavedButtonDelegate
extension HistoryTableViewController: RestaurantTableViewCellSavedButtonDelegate {
    
    func favoriteRestaurantButton(for cell: RestaurantTableViewCell) {
        guard let currentUser = UserController.shared.currentUser,
            let restaurant = cell.restaurant
            else { return }
        
        if currentUser.favoriteRestaurants.contains(restaurant.restaurantID) {
            // Remove the restaurant from the user's list of favorite restaurants
            currentUser.favoriteRestaurants.removeAll(where: {$0 == restaurant.restaurantID})
            
            // Remove the restaurant from the source of truth
            RestaurantController.shared.favoriteRestaurants?.removeAll(where: { $0 == restaurant })
            
            // Save the changes to the user
            UserController.shared.saveChanges(to: currentUser) { [weak self] (result) in
                switch result {
                case .success(_):
                    // Send the notification to update the saved restaurants list
                    NotificationCenter.default.post(Notification(name: updateSavedList))
                case .failure(let error):
                    // Print and display the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    DispatchQueue.main.async { self?.presentErrorAlert(error) }
                }
            }
        }
        else {
            // Add the restaurant from the user's list of favorite restaurants
            currentUser.favoriteRestaurants.append(restaurant.restaurantID)
            
            // Add the restaurant to the source of truth
            RestaurantController.shared.favoriteRestaurants?.append(restaurant)
            
            // Save the changes to the user
            UserController.shared.saveChanges(to: currentUser) { [weak self] (result) in
                switch result {
                case .success(_):
                    // Send the notification to update the saved restaurants list
                    NotificationCenter.default.post(Notification(name: updateSavedList))
                case .failure(let error):
                    // Print and display the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    DispatchQueue.main.async { self?.presentErrorAlert(error) }
                }
            }
        }
    }
    
    func blacklistRestaurantButton(for cell: RestaurantTableViewCell) {
        // TODO: - fill this out
    }
}
