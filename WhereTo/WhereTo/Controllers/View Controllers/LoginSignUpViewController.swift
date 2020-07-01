//
//  LoginSignUpViewController.swift
//  WhereTo
//
//  Created by Shannon Draeker on 6/22/20.
//  Copyright © 2020 Shannon Draeker. All rights reserved.
//

import UIKit
import Firebase

class LoginSignUpViewController: UIViewController {
    
    // MARK: - Outlets
    
    @IBOutlet weak var signUpToggleButton: UIButton!
    @IBOutlet weak var loginToggleButton: UIButton!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var confirmPasswordTextField: UITextField!
    @IBOutlet weak var doneButton: UIButton!
    
    // MARK: - Properties
    
    var isSigningUp: Bool = true
    
    // MARK: - Lifecycle Methods

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Try to log the user in automatically
        autoLogin()
    }
    
    // MARK: - Actions

    @IBAction func screenTapped(_ sender: UITapGestureRecognizer) {
        // Dismiss the keyboard
        emailTextField.resignFirstResponder()
        usernameTextField.resignFirstResponder()
        passwordTextField.resignFirstResponder()
        confirmPasswordTextField.resignFirstResponder()
    }
    
    @IBAction func signUpToggleButtonTapped(_ sender: UIButton) {
        UIView.animate(withDuration: 0.2) {
            self.isSigningUp = true
            
            self.signUpToggleButton.setTitleColor(.systemBlue, for: .normal)
            self.loginToggleButton.setTitleColor(.systemGray4, for: .normal)
            
            self.usernameTextField.isHidden = false
            self.confirmPasswordTextField.isHidden = false
            
            self.doneButton.setTitle("Sign Up", for: .normal)
        }
    }
    
    @IBAction func loginToggleButtonTapped(_ sender: UIButton) {
        toggleToLogin()
    }
    
    func toggleToLogin() {
        UIView.animate(withDuration: 0.2) {
            self.isSigningUp = false
            
            self.signUpToggleButton.setTitleColor(.systemGray4, for: .normal)
            self.loginToggleButton.setTitleColor(.systemBlue, for: .normal)
            
            self.usernameTextField.isHidden = true
            self.confirmPasswordTextField.isHidden = true
            
            self.doneButton.setTitle("Login", for: .normal)
        }
    }
    
    @IBAction func doneButtonTapped(_ sender: UIButton) {
        // Make sure there is valid text in the email and password fields
        guard let email = emailTextField.text, !email.isEmpty else {
            presentAlert(title: "Invalid Email", message: "Email cannot be blank")
            return
        }
        guard let password = passwordTextField.text, !password.isEmpty else {
            presentAlert(title: "Invalid Password", message: "Password cannot be blank")
            return
        }
        
        // Either sign up or login
        if isSigningUp { signUp(with: email, password: password) }
        else { login(with: email, password: password) }
    }
    
    // MARK: - Helper Methods
    
    // Try to log the user in automatically
    func autoLogin() {
        if let user = Auth.auth().currentUser {
            // If the user's email account has not yet been verified, don't sign in
            guard user.isEmailVerified else { return }
            self.view.activityStartAnimating(activityColor: UIColor.darkGray, backgroundColor: UIColor.clear)
            UserController.shared.fetchCurrentUser { [weak self] (result) in
                DispatchQueue.main.async {
                    switch result {
                    case .success(_):
                        self?.goToMainApp()
                        self?.view.activityStopAnimating()
                    case .failure(let error):
                        print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                        self?.view.activityStopAnimating()
                    }
                }
            }
        }
    }
    
    // Present an alert prompting the user to verify their email address
    func presentVerifyEmailAlert(with email: String) {
        // FIXME: - allow user to edit email address
        // FIXME: - refactor to elsewhere
        
        // Create the alert controller
        let alertController = UIAlertController(title: "Verify Email Address", message: "Please check your email \(email) to verify your email address", preferredStyle: .alert)
        
        // Create the button to resend the email
        let resendAction = UIAlertAction(title: "Resend Email", style: .cancel) { [weak self] (_) in
            Auth.auth().currentUser?.sendEmailVerification(completion: { (error) in
                if let error = error {
                    // Print and display the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    DispatchQueue.main.async { self?.presentErrorAlert(error) }
                }
                
                // Present the same alert telling them to check their email
                self?.presentVerifyEmailAlert(with: email)
            })
        }
        
        // Create the button to continue and check for verification
        let continueAction = UIAlertAction(title: "Log In", style: .default) { [weak self] (_) in
            self?.toggleToLogin()
            self?.emailTextField.text = email
        }
        
        // Add the buttons and present the alert
        alertController.addAction(resendAction)
        alertController.addAction(continueAction)
        present(alertController, animated: true)
    }
    
    // Create a new user
    func signUp(with email: String, password: String) {
        // Make sure the email doesn't already exist
        // TODO: - fill this out later
        
        // Make sure the username isn't blank
        guard usernameTextField.text == nil || usernameTextField.text != "" else {
            presentAlert(title: "Invalid Username", message: "Username can't be blank")
            return
        }
        
        // Make sure the passwords match
        guard confirmPasswordTextField.text == password else {
            presentAlert(title: "Passwords Do Not Match", message: "The passwords do not match - make sure to enter passwords carefully")
            return
        }
        
        // TODO: - display loading icon
        
        // Create the user and send the notification email
        self.view.activityStartAnimating(activityColor: UIColor.darkGray, backgroundColor: UIColor.clear)
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] (authResult, error) in
            guard authResult?.user != nil, error == nil else {
                // If the error is that the user name already exists, try to log in to that account
                // Print and display the error
                print("Error in \(#function) : \(error!.localizedDescription) \n---\n \(error!)")
                self?.view.activityStopAnimating()
                DispatchQueue.main.async { self?.presentErrorAlert(error!) }
                return
            }
            
            // Send an email to verify the user's email address
            Auth.auth().currentUser?.sendEmailVerification(completion: { (error) in
                
                if let error = error {
                    // Print and display the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    self?.view.activityStopAnimating()
                    DispatchQueue.main.async { self?.presentErrorAlert(error) }
                }
                
                // Present an alert asking them to check their email
                self?.presentVerifyEmailAlert(with: email)
            })
        }
    }
    
    // If the user already exists, log them in
    func login(with email: String, password: String) {
        self.view.activityStartAnimating(activityColor: UIColor.darkGray, backgroundColor: UIColor.clear)
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] (authResult, error) in
            if let error = error {
                // Print and display the error
                print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                self?.view.activityStopAnimating()
                DispatchQueue.main.async { self?.presentErrorAlert(error) }
                return
            }
            
            // Make sure the email is verified
            if Auth.auth().currentUser?.isEmailVerified ?? false {
                // Try to fetch the current user
                UserController.shared.fetchCurrentUser { (result) in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(_):
                            // Navigate to the main screen of the app
                            self?.view.activityStopAnimating()
                            self?.goToMainApp()
                        case .failure(let error):
                            // If the error is that the user doesn't exist yet, then create it
                            if case WhereToError.noUserFound = error {
                                self?.setUpUser(with: email)
                                self?.view.activityStopAnimating()
                                return
                            }
                            // Print and display the error
                            print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                            self?.view.activityStopAnimating()
                            self?.presentErrorAlert(error)
                        }
                    }
                }
            } else {
                // Present the alert asking the user to check their email
                self?.view.activityStopAnimating()
                self?.presentVerifyEmailAlert(with: email)
            }
        }
    }
    
    // Once a user has verified their email, finish completing their account
    func setUpUser(with email: String) {
        self.view.activityStartAnimating(activityColor: UIColor.darkGray, backgroundColor: UIColor.clear)
        UserController.shared.newUser(with: email, name: usernameTextField.text) { [weak self] (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self?.view.activityStopAnimating()
                    // Navigate to the main screen of the app
                    self?.goToMainApp()
                case .failure(let error):
                    // Print and display the error
                    print("Error in \(#function) : \(error.localizedDescription) \n---\n \(error)")
                    self?.view.activityStopAnimating()
                    self?.presentErrorAlert(error)
                }
            }
        }
    }
    
    // Go to the main app screen
    func goToMainApp() {
        transitionToStoryboard(named: .TabViewHome, direction: .fromRight)
    }
}
