//
//  FriendRequestController.swift
//  WhereTo
//
//  Created by Shannon Draeker on 6/22/20.
//  Copyright © 2020 Shannon Draeker. All rights reserved.
//

import Foundation
import Firebase

class FriendRequestController {
    
    // MARK: - Singleton
    
    static let shared = FriendRequestController()
    
    // MARK: - Properties
    
    let db = Firestore.firestore()
    typealias resultCompletion = (Result<Bool, WhereToError>) -> Void
    typealias resultCompletionWithObjects = (Result<[FriendRequest], WhereToError>) -> Void
    
    // MARK: - CRUD Methods
    
    // Create a new friend request
    func sendFriendRequest(to user: User, addingFriend: Bool = true, completion: @escaping resultCompletion) {
        guard let currentUser = UserController.shared.currentUser else { return completion(.failure(.noUserFound)) }
        
        // Create a new friend request
        let friendRequest = FriendRequest(fromID: currentUser.uuid, fromName: currentUser.name, toID: user.uuid, toName: user.name, status: (addingFriend ? .waiting : .removingFriend))
        
        // Save it to the cloud
        db.collection(FriendRequestStrings.recordType)
            .document("\(friendRequest.fromID)-\(friendRequest.toID)")
            .setData(friendRequest.asDictionary()) { (error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                // Return the success
                return completion(.success(true))
        }
    }
    
    // Create a request to remove a friend
    func sendRequestToRemove(_ user: User, completion: @escaping resultCompletion) {
        guard let currentUser = UserController.shared.currentUser else { return completion(.failure(.noUserFound)) }
        
        // Remove the friend from the user's list of friends
        currentUser.friends.removeAll(where: { $0 == user.uuid })
        
        // Save the changes to the user
        UserController.shared.saveChanges(to: user) { [weak self] (result) in
            switch result {
            case .success(_):
                // Send the notification to the unfriended user
                self?.sendFriendRequest(to: user, addingFriend: false, completion: completion)
            case .failure(let error):
                // Print and return the error
                print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                return completion(.failure(error))
            }
        }
    }
    
    // Read (fetch) all pending friend requests
    func fetchPendingRequests(completion: @escaping resultCompletionWithObjects) {
        guard let currentUser = UserController.shared.currentUser else { return completion(.failure(.noUserFound)) }
        
        // Fetch the data from the cloud
        db.collection(FriendRequestStrings.recordType)
            .whereField(FriendRequestStrings.toIDKey, isEqualTo: currentUser.uuid)
            .whereField(FriendRequestStrings.statusKey, isEqualTo: FriendRequest.Status.waiting.rawValue)
            .getDocuments { (results, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                
                // Unwrap the data
                guard let documents = results?.documents else { return completion(.failure(.couldNotUnwrap)) }
                let pendingFriendRequests = documents.compactMap { FriendRequest(dictionary: $0.data()) }
                
                // Return the success
                return completion(.success(pendingFriendRequests))
        }
    }
    
    // Update a friend request with a response
    func respondToFriendRequest(_ friendRequest: FriendRequest, accept: Bool, completion: @escaping resultCompletion) {
        guard let currentUser = UserController.shared.currentUser else { return completion(.failure(.noUserFound)) }
        
        // Update the friend request
        friendRequest.status = accept ? .accepted : .denied
        
        // Add the friend to the user's list of friends
        currentUser.friends.append(friendRequest.fromID)
        
        // Save the changes to the user
        UserController.shared.saveChanges(to: currentUser) { (_) in }
        
        // Save the changes to the friend request
        db.collection(FriendRequestStrings.recordType)
            .document("\(friendRequest.fromID)-\(friendRequest.toID)")
            .updateData([FriendRequestStrings.statusKey : friendRequest.status.rawValue]) { (error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                    // Otherwise return the success
                else { return completion(.success(true)) }
        }
    }
    
    // Delete a friend request when it's no longer needed
    func delete(_ friendRequest: FriendRequest, completion: @escaping resultCompletion) {
        // Delete the friend request from the cloud
        db.collection(FriendRequestStrings.recordType)
            .document("\(friendRequest.fromID)-\(friendRequest.toID)")
            .delete() { (error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                    // Otherwise return the success
                else { return completion(.success(true)) }
        }
    }
    
    // MARK: - Set Up Notifications
    
    func subscribeToFriendRequestNotifications() {
        guard let currentUser = UserController.shared.currentUser else { return }
        
        // Set up a listener to be alerted of any adding-type friend requests with the current user as the recipient
        db.collection(FriendRequestStrings.recordType)
            .whereField(FriendRequestStrings.toIDKey, isEqualTo: currentUser.uuid)
            .whereField(FriendRequestStrings.statusKey, isEqualTo: FriendRequest.Status.waiting.rawValue)
            .addSnapshotListener { (snapshot, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return
                }
                
                // Unwrap the data
                guard let documents = snapshot?.documents else { return }
                let newFriendRequests = documents.compactMap { FriendRequest(dictionary: $0.data()) }
                
                for friendRequest in newFriendRequests {
                    // Send a local notification to present an alert
                    NotificationCenter.default.post(name: newFriendRequest, object: friendRequest)
                    // FIXME: - need to figure out how this works when there are multiple friend requests
                }
        }
    }
    
    func subscribeToFriendRequestResponseNotifications() {
        guard let currentUser = UserController.shared.currentUser else { return }
        
        // Set up a listener to be alerted of changes to friend requests with the current user as the sender
        db.collection(FriendRequestStrings.recordType)
            .whereField(FriendRequestStrings.fromIDKey, isEqualTo: currentUser.uuid)
            .addSnapshotListener { [weak self] (snapshot, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return
                }
                
                // Unwrap the data
                guard let documents = snapshot?.documents else { return }
                let newResponses = documents.compactMap { FriendRequest(dictionary: $0.data()) }
                
                // If the request was accepted, add the friends to the user's list of friends
                currentUser.friends.append(contentsOf: newResponses.filter({ $0.status == .accepted }).map({ $0.toID }))
                
                // Save the changes to the user
                UserController.shared.saveChanges(to: currentUser) { (_) in }
                
                for response in newResponses {
                    // Send a local notification to present an alert and update the tableview as necessary
                    NotificationCenter.default.post(name: responseToFriendRequest, object: response)
                    NotificationCenter.default.post(Notification(name: updateFriendsList))
                    
                    // Delete the requests from the cloud now that they're no longer necessary
                    self?.delete(response, completion: { (_) in })
                }
        }
    }
    
    // When someone removes the current user as a friend
    func subscribeToRemovingFriendNotifications() {
        guard let currentUser = UserController.shared.currentUser else { return }
        
        // Set up a listener to be alerted of any removing-type friend requests with the current user as the recipient
        db.collection(FriendRequestStrings.recordType)
            .whereField(FriendRequestStrings.toIDKey, isEqualTo: currentUser.uuid)
            .whereField(FriendRequestStrings.statusKey, isEqualTo: FriendRequest.Status.removingFriend.rawValue)
            .addSnapshotListener { [weak self] (snapshot, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return
                }
                
                // Unwrap the data
                guard let documents = snapshot?.documents else { return }
                let friendsRemoving = documents.compactMap { FriendRequest(dictionary: $0.data()) }
                let friendsIDs = friendsRemoving.compactMap { $0.fromID }
                
                // Remove the friends from the users list of friends
                currentUser.friends.removeAll(where: { friendsIDs.contains($0) })
                
                // Save the changes to the user
                UserController.shared.saveChanges(to: currentUser) { (_) in }
                
                // Delete the requests from the cloud now that they're no longer necessary
                friendsRemoving.forEach({ self?.delete($0, completion: { (_) in }) })
                
                // Send a local notification to update the tableview
                // TODO: - need to present an alert to the user
        }
    }
}
