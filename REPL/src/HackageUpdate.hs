{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module HackageUpdate (
                      performArchiveFileUpdate, 
                      calcUpdateResultIO) where

import qualified Data.ByteString.Lazy as BL
import Data.Int(Int64)

import HttpDownload
import FileUtils
import Common

-- The action, that is needed to perform to correctly update the downloaded
-- archive. ArchiveIsOk - everything is fine.
-- Update - need to add some information to the end of the file
-- Reload - need to redownload the whole archive completely
data UpdateResult = ArchiveIsOk | Corrupted | Update Range deriving (Eq, Show)

-- The maximum range to download in one request from the hackage
maxRange :: Int64
maxRange = 512000

-- Calculates the update result of the current archive using two snapshots
calcUpdateResult :: HackageSnapshotData -> FileSnapshotData -> UpdateResult
calcUpdateResult hackage file 
  | hackage == file = ArchiveIsOk -- both are equal
  | lenH > lenF = Update (lenF, lenH - 1) -- need to append a bit
  | otherwise = Corrupted -- the file is of desired length, but the md5 does not match
  where lenH = lengthFile hackage
        lenF = lengthFile file

-- Calculates the update range in the IO monad
-- I didn't know how to name this method, so just added 2 to the end
calcUpdateResultIO :: FilePath -> URL -> IO (UpdateResult, HackageSnapshotData, FileSnapshotData)
calcUpdateResultIO file json = do
  snapshot <- fetchSnapshot json
  fileData <- calcFileData file
  return (calcUpdateResult snapshot fileData, snapshot, fileData)


-- performs the update, returns True if the the archive was modified
performArchiveFileUpdate :: URL -> URL -> FilePath -> IO UpdateResult
performArchiveFileUpdate snapshotURL archiveURL archive = do
  putStrLn $ "Updating " ++ archive ++ " from " ++ archiveURL
  (status, snapshot, _) <- calcUpdateResultIO archive snapshotURL

  case status of 
    ArchiveIsOk ->  (putStrLn $ "Archive is up to date") >> return ArchiveIsOk
    _ -> cutUpdate modifFunctions
  where 
    performUpdate = updateArchive archive archiveURL
    modifFunctions = [return (), cutting 50000, cutting 500000, cutting 5000000, removing]    
    cutting val = do
      putStrLn $ "\tCutting " ++ (show val) ++ " from " ++ archive
      truncateIfExists archive val
    removing = do
      putStrLn $ "\tRemoving " ++ archive
      removeIfExists archive

    cutUpdate (mf : mfs) = do
      mf
      (status, snapshot, _) <- calcUpdateResultIO archive snapshotURL
      case status of 
        ArchiveIsOk -> return ArchiveIsOk
        Corrupted -> cutUpdate mfs 
        Update range -> do
          putStrLn $ "\tSnapshot from " ++ snapshotURL ++ " " ++ (show snapshot)
          putStrLn $ "\tUpdate range " ++ (show range)
          result <- performUpdate snapshot range
          if result then return status
                    else cutUpdate mfs
    cutUpdate [] = do
      putStrLn "Failed to update"
      return Corrupted

updateArchive :: FilePath -> URL -> HackageSnapshotData -> Range -> IO Bool
updateArchive archive archiveURL snapshot range = do
  mapM_  (write2File archive archiveURL) (cropRanges maxRange range)
  newFileData <- calcFileData archive
  return (newFileData == snapshot)

write2File :: FilePath -> URL -> Range -> IO() 
write2File archive url range = do
  putStrLn $ "\tGetting range " ++ (show range) ++ " from " ++ url
  body <- fetchRangeData url range
  putStrLn $ "\tGot range " ++ (show (BL.take 50 body))
  BL.appendFile archive body
  putStrLn "Append ok"

