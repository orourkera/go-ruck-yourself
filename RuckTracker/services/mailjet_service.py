"""
Mailjet service for email marketing and user sync
"""
import json
import logging
import os
import requests
import base64
from typing import Dict, Any, Optional, List

logger = logging.getLogger(__name__)

class MailjetService:
    """Service for syncing users with Mailjet email marketing platform"""
    
    def __init__(self):
        """
        Initialize Mailjet service using API key authentication
        """
        logger.info("📧 MAILJET SERVICE INITIALIZATION START")
        
        self.api_key = os.getenv('MAILJET_API_KEY')
        self.api_secret = os.getenv('MAILJET_API_SECRET')
        self.contact_list_id = os.getenv('MAILJET_CONTACT_LIST_ID')  # Optional default list
        
        logger.info(f"📧 API Key: {'✅ Present' if self.api_key else '❌ Missing'}")
        logger.info(f"📧 API Secret: {'✅ Present' if self.api_secret else '❌ Missing'}")
        logger.info(f"📧 Default Contact List ID: {self.contact_list_id or 'None'}")
        
        # Mailjet API endpoints
        self.base_url = "https://api.mailjet.com/v3/REST"
        self.contacts_url = f"{self.base_url}/contact"
        self.contactslist_url = f"{self.base_url}/contactslist"
        self.listrecipient_url = f"{self.base_url}/listrecipient"
        
        # Basic auth header
        if self.api_key and self.api_secret:
            credentials = base64.b64encode(f"{self.api_key}:{self.api_secret}".encode()).decode()
            self.headers = {
                'Authorization': f'Basic {credentials}',
                'Content-Type': 'application/json'
            }
            logger.info("✅ Mailjet authentication headers configured")
        else:
            self.headers = None
            logger.error("❌ CRITICAL: Mailjet API credentials not configured")
    
    def _is_configured(self) -> bool:
        """Check if Mailjet service is properly configured"""
        return bool(self.api_key and self.api_secret and self.headers)
    
    def create_or_update_contact(self, email: str, name: str = None, properties: Dict[str, Any] = None) -> bool:
        """
        Create or update a contact in Mailjet
        
        Args:
            email: Contact email address
            name: Contact name (optional)
            properties: Additional contact properties (optional)
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self._is_configured():
            logger.error("❌ Mailjet service not configured - skipping contact sync")
            return False
        
        try:
            logger.info(f"📧 Creating/updating Mailjet contact: {email}")
            
            # Prepare contact data
            contact_data = {
                "Email": email,
                "IsExcludedFromCampaigns": False
            }
            
            if name:
                contact_data["Name"] = name
            
            # Add custom properties if provided (skip for now to avoid API errors)
            # Custom properties require pre-defined contact properties in Mailjet
            if properties:
                logger.debug(f"📧 Skipping custom properties to avoid API errors: {list(properties.keys())}")
                # contact_data.update(properties)  # Commented out to prevent API errors
            
            # Create or update contact using PUT (upsert)
            response = requests.put(
                self.contacts_url,
                headers=self.headers,
                json=contact_data
            )
            
            if response.status_code in [200, 201]:
                result = response.json()
                logger.info(f"✅ Contact sync successful: {email}")
                logger.debug(f"📧 Mailjet response: {result}")
                return True
            else:
                logger.error(f"❌ Failed to sync contact {email}: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Error syncing contact {email} to Mailjet: {e}", exc_info=True)
            return False
    
    def add_contact_to_list(self, email: str, list_id: str = None) -> bool:
        """
        Add a contact to a specific mailing list
        
        Args:
            email: Contact email address
            list_id: Mailjet list ID (uses default if not provided)
            
        Returns:
            bool: True if successful, False otherwise
        """
        if not self._is_configured():
            logger.error("❌ Mailjet service not configured - skipping list addition")
            return False
        
        target_list_id = list_id or self.contact_list_id
        if not target_list_id:
            logger.warning(f"⚠️ No list ID provided for contact {email} - skipping list addition")
            return False
        
        try:
            logger.info(f"📧 Adding contact {email} to Mailjet list {target_list_id}")
            
            # Add contact to list
            list_data = {
                "ContactAlt": email,
                "ListID": target_list_id,
                "IsActive": True
            }
            
            response = requests.post(
                self.listrecipient_url,
                headers=self.headers,
                json=list_data
            )
            
            if response.status_code in [200, 201]:
                result = response.json()
                logger.info(f"✅ Contact {email} added to list {target_list_id}")
                logger.debug(f"📧 Mailjet list response: {result}")
                return True
            elif response.status_code == 400:
                # Check if it's because contact is already in list
                error_text = response.text.lower()
                if "already exists" in error_text or "duplicate" in error_text:
                    logger.info(f"ℹ️ Contact {email} already in list {target_list_id}")
                    return True
                else:
                    logger.error(f"❌ Failed to add contact {email} to list: {response.status_code} - {response.text}")
                    return False
            else:
                logger.error(f"❌ Failed to add contact {email} to list: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Error adding contact {email} to Mailjet list {target_list_id}: {e}", exc_info=True)
            return False
    
    def sync_user_signup(self, email: str, username: str = None, user_metadata: Dict[str, Any] = None) -> bool:
        """
        Sync a new user signup to Mailjet
        
        Args:
            email: User email address
            username: User display name
            user_metadata: Additional user data (signup date, source, etc.)
            
        Returns:
            bool: True if successful, False otherwise
        """
        logger.info(f"📧 MAILJET USER SIGNUP SYNC: {email}")
        
        try:
            # For now, just sync email and name without custom properties
            # Custom properties require pre-defined contact properties in Mailjet
            logger.debug(f"📧 Syncing basic contact info for {email}")
            if user_metadata:
                logger.debug(f"📧 User metadata available but skipping custom properties: {list(user_metadata.keys())}")
            
            # Create/update the contact with basic info only
            success = self.create_or_update_contact(
                email=email,
                name=username,
                properties=None  # Skip custom properties for now
            )
            
            if not success:
                return False
            
            # Add to default mailing list if configured
            if self.contact_list_id:
                list_success = self.add_contact_to_list(email)
                if not list_success:
                    logger.warning(f"⚠️ Contact created but failed to add to default list: {email}")
                    # Don't return False here - contact creation succeeded
            
            logger.info(f"✅ MAILJET SYNC COMPLETE: {email}")
            return True
            
        except Exception as e:
            logger.error(f"❌ MAILJET SYNC FAILED for {email}: {e}", exc_info=True)
            return False
    
    def get_contact_lists(self) -> List[Dict[str, Any]]:
        """
        Get all available contact lists
        
        Returns:
            List of dictionaries containing list information
        """
        if not self._is_configured():
            logger.error("❌ Mailjet service not configured")
            return []
        
        try:
            response = requests.get(
                self.contactslist_url,
                headers=self.headers
            )
            
            if response.status_code == 200:
                result = response.json()
                lists = result.get('Data', [])
                logger.info(f"📧 Found {len(lists)} Mailjet contact lists")
                return lists
            else:
                logger.error(f"❌ Failed to fetch contact lists: {response.status_code} - {response.text}")
                return []
                
        except Exception as e:
            logger.error(f"❌ Error fetching Mailjet contact lists: {e}", exc_info=True)
            return []
    
    def test_connection(self) -> bool:
        """
        Test the Mailjet API connection
        
        Returns:
            bool: True if connection is working, False otherwise
        """
        if not self._is_configured():
            logger.error("❌ Mailjet service not configured")
            return False
        
        try:
            # Test with a simple API call to get account info
            response = requests.get(
                f"{self.base_url}/apikey",
                headers=self.headers
            )
            
            if response.status_code == 200:
                logger.info("✅ Mailjet connection test successful")
                return True
            else:
                logger.error(f"❌ Mailjet connection test failed: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Mailjet connection test error: {e}", exc_info=True)
            return False


# Global service instance
_mailjet_service = None

def get_mailjet_service() -> MailjetService:
    """
    Get singleton instance of MailjetService
    
    Returns:
        MailjetService instance
    """
    global _mailjet_service
    if _mailjet_service is None:
        _mailjet_service = MailjetService()
    return _mailjet_service


def sync_user_to_mailjet(email: str, username: str = None, user_metadata: Dict[str, Any] = None) -> bool:
    """
    Helper function to sync a user to Mailjet
    
    Args:
        email: User email address
        username: User display name
        user_metadata: Additional user data
        
    Returns:
        bool: True if successful, False otherwise
    """
    try:
        mailjet = get_mailjet_service()
        return mailjet.sync_user_signup(email, username, user_metadata)
    except Exception as e:
        logger.error(f"❌ Failed to sync user {email} to Mailjet: {e}", exc_info=True)
        return False
