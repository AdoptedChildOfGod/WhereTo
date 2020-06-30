//
//  UserController.swift
//  WhereTo
//
//  Created by Shannon Draeker on 6/22/20.
//  Copyright © 2020 Shannon Draeker. All rights reserved.
//

import Foundation
import Firebase

class UserController {
    
    // MARK: - Singleton
    
    static let shared = UserController()
    
    // MARK: - Source of Truth
    
    var currentUser: User?
    var friends: [User]?
    
    // MARK: - Properties
    
    let db = Firestore.firestore()
    typealias resultCompletion = (Result<Bool, WhereToError>) -> Void
    typealias resultCompletionWithObject = (Result<User, WhereToError>) -> Void
    
    // MARK: - CRUD Methods
    
    // Create a new user
    func newUser(with email: String, name: String?, completion: @escaping resultCompletion) {
        let user = User(email: email, name: (name ?? email.components(separatedBy: "@").first) ?? email)
        
        // Save the user object to the cloud and save the documentID for editing purposes
        let reference: DocumentReference = db.collection(UserStrings.recordType).addDocument(data: user.asDictionary()) { (error) in
            
            if let error = error {
                // Print and return the error
                print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                return completion(.failure(.fsError(error)))
            }
        }
        // FIXME: - threading issue here, but need reference outside
        user.documentID = reference.documentID
        
        // Save to the source of truth and return the success
        currentUser = user
        setUpUser()
        return completion(.success(true))
    }
    
    // Read (fetch) the current user
    func fetchCurrentUser(completion: @escaping resultCompletion) {
        guard let user = Auth.auth().currentUser, let email = user.email else { return completion(.failure(.noUserFound)) }
        
        db.collection(UserStrings.recordType)
            .whereField(UserStrings.emailKey, isEqualTo: email)
            .getDocuments { [weak self] (results, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                
                // Unwrap the data
                guard let documents = results?.documents,
                    documents.count > 0
                    else { return completion(.failure(.noUserFound)) }
                guard let document = documents.first else { return completion(.failure(.couldNotUnwrap)) }
                let currentUser = User(dictionary: document.data())
                currentUser?.documentID = document.documentID
                
                // Save to the source of truth and return the success
                self?.currentUser = currentUser
                self?.setUpUser()
                return completion(.success(true))
        }
    }
    
    // Read (search for) a specific user
    func searchFor(email: String, completion: @escaping resultCompletionWithObject) {
        // Fetch the data from the cloud
        db.collection(UserStrings.recordType)
            .whereField(UserStrings.emailKey, isEqualTo: email)
            .getDocuments { (results, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                
                // Unwrap the data
                guard let document = results?.documents.first
                    else { return completion(.failure(.noSuchUser))}
                guard let friend = User(dictionary: document.data())
                    else { return completion(.failure(.couldNotUnwrap)) }
                
                // Return the success
                return completion(.success(friend))
        }
    }
    
    // Read (fetch) the user's friends
    func fetchUsersFriends(completion: @escaping resultCompletion) {
        guard let currentUser = self.currentUser else { return completion(.failure(.noUserFound)) }
        
        // Handle the edge case where the user has no friends
        if currentUser.friends.count == 0 {
            friends = []
            return completion(.success(true))
        }
        
        // Fetch the data from the cloud
        db.collection(UserStrings.recordType)
            .whereField(UserStrings.uuidKey, in: currentUser.friends)
            .getDocuments { [weak self] (results, error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                
                // Unwrap the data
                guard let documents = results?.documents else { return completion(.failure(.couldNotUnwrap)) }
                let friends = documents.compactMap({ User(dictionary: $0.data()) })
                
                // Save to the source of truth and return the success
                self?.friends = friends
                return completion(.success(true))
        }
    }
    
    // Update a user
    func saveChanges(to user: User, completion: @escaping resultCompletion) {
        guard let documentID = user.documentID else { return completion(.failure(.noUserFound)) }
        
        // Update the data in the cloud
        db.collection(UserStrings.recordType)
            .document(documentID)
            .updateData(user.asDictionary()) { [weak self] (error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                
                // Update the source of truth
                self?.currentUser = user
                
                // Return the success
                return completion(.success(true))
        }
    }
    
    // Delete a user
    // FIXME: - this doesn't quite work
    func deleteCurrentUser(completion: @escaping resultCompletion) {
        guard let currentUser = currentUser, let documentID = currentUser.documentID
            else { return completion(.failure(.noUserFound)) }
        
        // Delete the data from the cloud
        db.collection(UserStrings.recordType)
            .document(documentID)
            .delete() { (error) in
                
                if let error = error {
                    // Print and return the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    return completion(.failure(.fsError(error)))
                }
                
                let group = DispatchGroup()
                
                // Remove all friends, delete all outstanding friend requests, votes, and voting session invitations associated with the user
                if let friends = self.friends {
                    for friend in friends {
                        group.enter()
                        FriendRequestController.shared.sendRequestToRemove(friend, userBeingDeleted: true) { (result) in
                            switch result {
                            case .success(_):
                                print("successfully removed friend")
                            case .failure(let error):
                                // Print and return the error
                                print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                                return completion(.failure(error))
                            }
                            group.leave()
                        }
                    }
                }
                group.enter()
                FriendRequestController.shared.deleteAll { (error) in
                    if let error = error {
                        // Print and return the error
                        print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                        return completion(.failure(error))
                    }
                    group.leave()
                }
                group.enter()
                VotingSessionController.shared.deleteAllVotes { (error) in
                    if let error = error {
                        // Print and return the error
                        print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                        return completion(.failure(error))
                    }
                    group.leave()
                }
                group.enter()
                VotingSessionController.shared.deleteAllVotingInvites { (error) in
                    if let error = error {
                        // Print and return the error
                        print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                        return completion(.failure(error))
                    }
                    group.leave()
                }
                
                // Return the success
                group.notify(queue: .main) {  return completion(.success(true)) }
        }
    }
    
    // MARK: - Helper Methods
    
    func setUpUser() {
        FriendRequestController.shared.subscribeToFriendRequestNotifications()
        FriendRequestController.shared.subscribeToFriendRequestResponseNotifications()
        FriendRequestController.shared.subscribeToRemovingFriendNotifications()
        
        VotingSessionController.shared.subscribeToInvitationNotifications()
        VotingSessionController.shared.subscribeToInvitationResponseNotifications()
        VotingSessionController.shared.subscribeToSessionOverNotifications()
        VotingSessionController.shared.subscribeToVoteNotifications()
    }
}
