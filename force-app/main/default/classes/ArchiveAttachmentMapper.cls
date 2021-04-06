global class ArchiveAttachmentMapper implements Schedulable {
  global void execute(SchedulableContext ctx) {
    /**
     * Declare a list of File Reference Records
     * */
    List<Archived_Record_File_Reference__c> fileLinks = new List<Archived_Record_File_Reference__c>();

    /**
     * Case query with WHERE clause exactly like the query in Privacy Center.
     * The query can be viewed from the Retention Policy UI configurator.
     * This is hard coded here for POC but could include the same filters that are in the policy.
     */

    Map<Id, Case> archiveEligibleCases = new Map<Id, Case>(
      [
        SELECT Id, Archived_Record_File_Reference__c
        FROM Case
        WHERE Id = '5005Y00001vJWMeQAO'
      ]
    );

    Set<Id> caseIds = archiveEligibleCases.keySet();
    /**
     * Get a list of all the classic attachments for the Cases
     */
    List<Attachment> caseAttachments = [
      SELECT Id, Body, Name, Description, ParentId
      FROM Attachment
      WHERE ParentId IN :caseIds
    ];

    /**
     * Create a Set of Case Ids with Attachments
     * (We are using a set so we have unique records and Case Ids aren't repeated)
     */
    Set<Id> caseWtAttmnts = new Set<Id>();

    for (Attachment att : caseAttachments) {
      caseWtAttmnts.add(att.ParentId);
    }

    //Query all the Files attached to the cases

    List<ContentDocumentLink> attachedFiles = [
      SELECT
        ContentDocumentId,
        Id,
        IsDeleted,
        LinkedEntityId,
        ShareType,
        SystemModstamp,
        Visibility
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN :caseIds
    ];

    //Add the cases with files to the Set of File Reference Records.
    for (ContentDocumentLink cdl : attachedFiles) {
      caseWtAttmnts.add(cdl.LinkedEntityId);
    }

    if (caseWtAttmnts.size() > 0) {
      //Create a list of File Reference Records and create a record for each case with an attachment or File

      for (Id id : caseWtAttmnts) {
        Archived_Record_File_Reference__c fileLink = new Archived_Record_File_Reference__c();
        fileLink.Parent_Id__c = id;
        fileLinks.add(fileLink);
      }

      insert fileLinks;

      //Create a Map of the Archived Record Reference to the Un Archived Record

      Map<Id, Archived_Record_File_Reference__c> parentReferenceMap = new Map<Id, Archived_Record_File_Reference__c>();

      Set<Case> updatedCases = new Set<Case>();

      for (Archived_Record_File_Reference__c fl : fileLinks) {
        parentReferenceMap.put(fl.Parent_Id__c, fl);

        //Update the case with the Archived Record Link for this case to look back up from the External Object once it's archived
        archiveEligibleCases.get(fl.Parent_Id__c)
          .Archived_Record_File_Reference__c = fl.Id;
        updatedCases.add(archiveEligibleCases.get(fl.Parent_Id__c));
      }
      List<Case> uniqueCases = new List<Case>();
      uniqueCases.addAll(updatedCases);

      update uniqueCases;
      /**
       * Iterate over the Attachments, create a new attachment record, assign parent Id as Archived File Reference and clone the attachment
       */
      List<Attachment> archiveAttachments = new List<Attachment>();

      for (Attachment att : caseAttachments) {
        Attachment newAtt = att.clone();
        newAtt.ParentId = parentReferenceMap.get(att.ParentId).Id;
        archiveAttachments.add(newAtt);
      }

      if (archiveAttachments.size() > 0) {
        insert archiveAttachments;
      }

      List<ContentDocumentLink> archiveFiles = new List<ContentDocumentLink>();

      for (ContentDocumentLink cdl : attachedFiles) {
        ContentDocumentLink newCdl = cdl.clone();
        newCdl.LinkedEntityId = parentReferenceMap.get(cdl.LinkedEntityId).Id;
        archiveFiles.add(newCdl);
      }

      if (archiveFiles.size() > 0) {
        insert archiveFiles;
      }
    }
  }
}
