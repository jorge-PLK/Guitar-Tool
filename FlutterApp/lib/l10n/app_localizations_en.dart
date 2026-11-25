// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonAnchor => '';

  @override
  String get common_accept => 'OK';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_delete => 'Delete';

  @override
  String get shellAnchor => '';

  @override
  String get shell_appTitle => 'ToneForge';

  @override
  String get shell_logoForge => 'Forge';

  @override
  String get shell_logoTone => 'Tone';

  @override
  String get shell_navBacking => 'Backing track';

  @override
  String get shell_navLibrary => 'Library';

  @override
  String get shell_navMontage => 'Montage';

  @override
  String get shell_navRecord => 'Record';

  @override
  String get shell_navSettings => 'Settings';

  @override
  String get shell_navTab => 'Tabs';

  @override
  String get shell_selectedThemeHelp => 'Open the theme page';

  @override
  String shell_selectedThemeLabel(String title) {
    return 'Selected theme: $title';
  }

  @override
  String get libraryAnchor => '';

  @override
  String get library_artistsBack => 'Artists';

  @override
  String library_artistTileLabel(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$name, $_temp0';
  }

  @override
  String library_artistTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count songs',
      one: '1 song',
    );
    return '$_temp0';
  }

  @override
  String get library_cancel => 'Cancel';

  @override
  String library_cleanConfirm(String bytes) {
    return 'Clean $bytes';
  }

  @override
  String library_cleanMessage(String bytes) {
    return 'Discarded takes and stems taking up $bytes will be deleted. Stems can be generated again.';
  }

  @override
  String get library_cleanTitleAll => 'Clean the whole library';

  @override
  String library_cleanTitle(String title) {
    return 'Clean “$title”';
  }

  @override
  String get library_colSong => 'Song / Artist';

  @override
  String get library_colState => 'State';

  @override
  String get library_colTakes => 'Takes';

  @override
  String get library_deleteButton => 'Delete…';

  @override
  String get library_deleteLabel => 'Delete';

  @override
  String get library_deleteTooltip => 'Delete…';

  @override
  String get library_detailBack => 'Library';

  @override
  String get library_duplicateMessage =>
      'There is already a project with the same audio (same SHA-256) or the same source video. Do you want to open it?';

  @override
  String get library_duplicateOpen => 'Open the existing one';

  @override
  String get library_duplicateTitle => 'This song is already in the library';

  @override
  String get library_editSheetTitle => 'Fix title and artist';

  @override
  String get library_editTooltip => 'Edit title and artist';

  @override
  String get library_emptyBody =>
      'Import a wav, flac or mp3, drag it into this window, or paste a YouTube or Spotify link.';

  @override
  String get library_emptyTitle => 'No songs yet';

  @override
  String get library_errBusy =>
      'The song is busy (being separated or reprocessed).';

  @override
  String get library_errCancel => 'Couldn’t cancel';

  @override
  String get library_errClean => 'Couldn’t clean';

  @override
  String get library_errDelete => 'Couldn’t delete from disk';

  @override
  String get library_errDuplicate => 'That song is already in the library.';

  @override
  String library_errImportFile(String file) {
    return 'Couldn’t import $file';
  }

  @override
  String get library_errOpen => 'Couldn’t open the song';

  @override
  String get library_errProjectNotFound => 'The project isn’t in the folder.';

  @override
  String get library_errSave => 'Couldn’t save the title';

  @override
  String library_errSeparate(String title) {
    return 'Couldn’t separate $title';
  }

  @override
  String get library_errSeparateBar => 'Couldn’t separate';

  @override
  String get library_errTitleEmptyBody => 'The title can’t be empty.';

  @override
  String get library_errTitleEmptyTitle => 'Title missing';

  @override
  String library_errTrashBody(String error) {
    return '$error Nothing was deleted; you still have “Delete from disk”.';
  }

  @override
  String get library_errTrashTitleMac => 'Couldn’t move to Trash';

  @override
  String get library_errTrashTitleWindows => 'Couldn’t move to Recycle Bin';

  @override
  String get library_errUnsafeDeletion =>
      'The song folder is not a valid library project; nothing was deleted.';

  @override
  String get library_errWorkInProgress => 'A separation is running or queued.';

  @override
  String get library_fieldArtist => 'Artist';

  @override
  String get library_fieldTitle => 'Title';

  @override
  String get library_firstRunBody =>
      'Each song lives in its own folder, with its stems, takes and video. You can change it later in Settings.';

  @override
  String get library_firstRunChoose => 'Choose folder…';

  @override
  String library_firstRunProposal(String path) {
    return 'Suggested: $path';
  }

  @override
  String get library_firstRunTitle => 'Choose your project folder';

  @override
  String get library_importAlreadyLatest =>
      'yt-dlp is already the latest version: YouTube has changed something and a fix has to wait. Meanwhile, import the file by hand (Import song > Import file…).';

  @override
  String get library_importButton => 'Import song';

  @override
  String get library_importCancel => 'Cancel';

  @override
  String get library_importCandidatesLabel => 'CANDIDATES ON YOUTUBE';

  @override
  String get library_importChipClose => 'close';

  @override
  String get library_importChipInLibrary => 'In library';

  @override
  String get library_importChipLive => 'live';

  @override
  String get library_importChoose => 'Choose';

  @override
  String get library_importClose => 'Close';

  @override
  String get library_importConverting => 'Converting to WAV…';

  @override
  String get library_importDone => 'Song imported';

  @override
  String get library_importDownloading => 'Downloading audio…';

  @override
  String get library_importFailTitle => 'Couldn’t import';

  @override
  String get library_importFile => 'Import file…';

  @override
  String get library_importGo => 'Import';

  @override
  String get library_importImporting => 'Importing into the library…';

  @override
  String library_importing(String percent) {
    return 'Importing $percent';
  }

  @override
  String get library_importLinkHint => 'Paste a link or search Spotify';

  @override
  String get library_importListenTooltip => 'Listen on Spotify';

  @override
  String get library_importManualAdd => 'Add';

  @override
  String get library_importManualHint => 'https://www.youtube.com/watch?v=…';

  @override
  String get library_importManualLabel =>
      'None look right? Paste a YouTube link';

  @override
  String library_importNoClose(int seconds) {
    return 'No candidate is within $seconds s of the Spotify duration. Choose carefully or paste a YouTube link by hand.';
  }

  @override
  String get library_importNoResults =>
      'The search returned no results. Paste a YouTube link by hand.';

  @override
  String get library_importOpen => 'Open';

  @override
  String get library_importOpenBrowser => 'Open in browser';

  @override
  String get library_importOtherLink => 'Try another link';

  @override
  String get library_importPasteYt => 'Paste a YouTube link';

  @override
  String library_importPossible(String name) {
    return 'You may already have it: $name';
  }

  @override
  String get library_importPreparing => 'Preparing…';

  @override
  String get library_importReadingMeta => 'Reading metadata…';

  @override
  String get library_importRepeatedBody => 'Nothing is searched or downloaded.';

  @override
  String get library_importRepeatedTitle => 'Already in the library';

  @override
  String get library_importRetry => 'Retry';

  @override
  String get library_importSearchingYt => 'Searching YouTube…';

  @override
  String get library_importSlow => 'Usually takes about 9 s.';

  @override
  String library_importSpotifyDuration(String duration) {
    return 'Spotify: $duration';
  }

  @override
  String library_importSpotifyNone(String query) {
    return 'Spotify found nothing for “$query”';
  }

  @override
  String get library_importSupported =>
      'YouTube video links (youtube.com/watch, youtu.be, music.youtube.com) and Spotify song links (open.spotify.com/track or spotify:track) are supported, as well as YouTube playlists (youtube.com/playlist) and Spotify playlists or albums (open.spotify.com/playlist, open.spotify.com/album). Episodes are not.';

  @override
  String get library_importTitleEmpty => 'Import song';

  @override
  String get library_importTitleLink => 'Import from link';

  @override
  String get library_importTitleList => 'Import playlist';

  @override
  String get library_importUpdateRetry => 'Update and retry';

  @override
  String get library_importUpdating => 'Updating yt-dlp…';

  @override
  String get library_importVideoLabel => 'VIDEO TO IMPORT';

  @override
  String get library_infoDuration => 'Duration';

  @override
  String get library_infoRate => 'Rate';

  @override
  String get library_infoState => 'State';

  @override
  String get library_menuCancelSeparation => 'Cancel separation';

  @override
  String get library_menuClean => 'Clean…';

  @override
  String get library_menuDelete => 'Delete…';

  @override
  String get library_menuRevealMac => 'Show in Finder';

  @override
  String get library_menuRevealWindows => 'Show in File Explorer';

  @override
  String get library_menuSeparate => 'Separate again';

  @override
  String get library_noArtist => 'No artist';

  @override
  String library_noMatch(String query) {
    return 'No song matches “$query”';
  }

  @override
  String get library_noticeTitle => 'Notice';

  @override
  String get library_noticeOk => 'OK';

  @override
  String get library_openInBacking => 'Open in Backing track';

  @override
  String get library_playlistIndicatorTooltip => 'View the playlist import';

  @override
  String get library_plCancel => 'Cancel';

  @override
  String get library_plCancelledTitle =>
      'Queue cancelled: what’s already imported is kept.';

  @override
  String get library_plCap =>
      'Spotify returns at most 100 songs per playlist, so this one may be cut short. If songs are missing, import them from their link.';

  @override
  String get library_plChipDoubtful => 'doubtful';

  @override
  String get library_plChipMaybe => 'You may already have it';

  @override
  String library_plChoiceFailed(String title) {
    return 'Search failed: $title';
  }

  @override
  String get library_plChoiceNoResults => 'No results: skip';

  @override
  String get library_plChoicePending => 'Not searched';

  @override
  String get library_plChoicePick => 'Pick a candidate…';

  @override
  String get library_plChoiceSkipped => 'Skipped';

  @override
  String get library_plCloseTooltip =>
      'The queue keeps running in the background';

  @override
  String get library_plConverting => 'Converting…';

  @override
  String get library_plDefaultName => 'Playlist';

  @override
  String get library_plDoneTitle => 'Import finished';

  @override
  String library_plDownload(int n) {
    return 'Download and process ($n)';
  }

  @override
  String get library_plDownloading => 'Downloading…';

  @override
  String library_plDownloadingPercent(String percent) {
    return 'Downloading $percent';
  }

  @override
  String get library_plFailedHeader => 'FAILED';

  @override
  String get library_plIndCancelled => 'Import cancelled';

  @override
  String get library_plIndFinished => 'Import finished';

  @override
  String library_plIndImporting(int n, int total) {
    return 'Importing $n of $total';
  }

  @override
  String get library_plIndLoading => 'Reading the playlist…';

  @override
  String library_plIndSearching(int n, int total) {
    return 'Searching $n of $total';
  }

  @override
  String get library_plIndStopped => 'Import stopped';

  @override
  String library_plInLibrarySuffix(String label) {
    return '$label · In library';
  }

  @override
  String get library_plKeepSearching => 'Keep searching';

  @override
  String get library_plLatestKept =>
      'yt-dlp is already the latest version: YouTube has changed something and a fix has to wait. What’s already imported is kept.';

  @override
  String library_plMaybeTooltip(String title) {
    return 'Similar to: $title';
  }

  @override
  String get library_plNothingYet =>
      'Nothing is downloaded yet: you can review the candidates afterwards.';

  @override
  String library_plOpenExisting(String title) {
    return 'Open “$title” in the library';
  }

  @override
  String get library_plQImported => 'Imported';

  @override
  String get library_plQInLibrary => 'In library';

  @override
  String get library_plQQueued => 'Queued';

  @override
  String get library_plQSkipped => 'Skipped';

  @override
  String library_plQueueCount(int done, int total) {
    return '$done of $total songs';
  }

  @override
  String get library_plQueueStopped => 'Queue stopped';

  @override
  String get library_plQueueTitle => 'Downloading, importing and separating';

  @override
  String get library_plRateLimitedHint =>
      'It won’t retry on its own: resume when you like.';

  @override
  String get library_plResume => 'Resume';

  @override
  String library_plResumeN(int n) {
    return 'Resume ($n)';
  }

  @override
  String library_plRetryFailed(int n) {
    return 'Retry failed ($n)';
  }

  @override
  String get library_plReviewBanner =>
      'Review the suggestions: nothing is downloaded until you press “Download and process”. “Doubtful” songs have no suggestion: pick one or they are skipped.';

  @override
  String library_plReviewSummary(int proposed, int doubtful, int skipped) {
    return '$proposed with a candidate · $doubtful doubtful · $skipped skipped';
  }

  @override
  String library_plSearch(int n) {
    return 'Search on YouTube ($n)';
  }

  @override
  String get library_plSearchingAll => 'Searching each song on YouTube';

  @override
  String library_plSearchingN(int n, int total) {
    return 'Searching $n of $total';
  }

  @override
  String get library_plSelectAll => 'Select all';

  @override
  String get library_plSelectNone => 'None';

  @override
  String get library_plSeparatingNote =>
      'Imported songs are being separated into stems; you’ll see progress in the Library.';

  @override
  String get library_plSkipItem => 'Skip this song';

  @override
  String get library_plStatFailed => 'Failed';

  @override
  String get library_plStatImported => 'Imported';

  @override
  String get library_plStatInLibrary => 'Already in library';

  @override
  String get library_plStatSkipped => 'Skipped';

  @override
  String library_plSummary(int total, int selected) {
    return '$total songs · $selected selected';
  }

  @override
  String library_plSummaryInLibrary(int n) {
    return ' · $n already in the library';
  }

  @override
  String get library_plUpdateRetry => 'Update and retry';

  @override
  String get library_plUpdating => 'Updating…';

  @override
  String get library_recordingsNone => 'This song has no recorded takes yet.';

  @override
  String get library_recordingsTitle => 'Recordings';

  @override
  String get library_revealButtonMac => 'Show in Finder';

  @override
  String get library_revealButtonWindows => 'Show in File Explorer';

  @override
  String get library_revealTooltipMac => 'Show in Finder';

  @override
  String get library_revealTooltipWindows => 'Show in File Explorer';

  @override
  String get library_save => 'Save';

  @override
  String get library_searchClear => 'Clear search';

  @override
  String get library_searchHint => 'Search song or artist';

  @override
  String get library_srcAgeRestrictedDetail =>
      'Age-restricted video: it can’t be downloaded without an account.';

  @override
  String get library_srcAgeRestrictedTitle => 'Age-restricted video';

  @override
  String get library_srcCancelledTitle => 'Cancelled';

  @override
  String get library_srcChecksumDetail =>
      'The SHA-256 checksum of the downloaded yt-dlp doesn’t match. Nothing was installed.';

  @override
  String get library_srcChecksumTitle => 'Update rejected';

  @override
  String get library_srcExtractorBrokenDetail =>
      'YouTube changed something and yt-dlp can’t read it.';

  @override
  String get library_srcExtractorBrokenTitle => 'yt-dlp may be out of date';

  @override
  String library_srcExtractorBrokenTitleVersion(String version) {
    return 'yt-dlp may be out of date (version $version)';
  }

  @override
  String get library_srcFfmpegFailedTitle => 'Conversion failed';

  @override
  String library_srcHelperMissingDetail(String name) {
    return '“$name” was not found inside the app. Reinstall ToneForge.';
  }

  @override
  String get library_srcHelperMissingTitle => 'A component is missing';

  @override
  String library_srcHttpStatusDetail(int code) {
    return 'The server responded with code $code.';
  }

  @override
  String get library_srcHttpStatusTitle => 'Unexpected response';

  @override
  String get library_srcLaunchFailedTitle => 'Couldn’t start the process';

  @override
  String get library_srcNoAudioFormatDetail =>
      'This video doesn’t offer downloadable audio.';

  @override
  String get library_srcNoAudioFormatTitle => 'No downloadable audio';

  @override
  String get library_srcNoAudioProducedDetail =>
      'yt-dlp finished but left no audio file.';

  @override
  String get library_srcNoAudioProducedTitle => 'No audio';

  @override
  String get library_srcOfflineDetail =>
      'Couldn’t connect. Check your network and try again.';

  @override
  String get library_srcOfflineTitle => 'No connection';

  @override
  String get library_srcPrivateDetail => 'This video is private.';

  @override
  String get library_srcPrivateTitle => 'Private video';

  @override
  String get library_srcRateLimitedDetail =>
      'YouTube has limited requests; wait a few minutes and try again.';

  @override
  String get library_srcRateLimitedTitle => 'YouTube has limited requests';

  @override
  String get library_srcRegionDetail =>
      'This video isn’t available in your country.';

  @override
  String get library_srcRegionTitle => 'Not available in your region';

  @override
  String get library_srcRemovedDetail =>
      'This video has been removed or is no longer available.';

  @override
  String get library_srcRemovedTitle => 'Video unavailable';

  @override
  String get library_spotifyBadResponse =>
      'Spotify returned an unexpected response';

  @override
  String get library_spotifyMissingCredentials =>
      'Spotify search unavailable: the key (.env) is missing';

  @override
  String get library_spotifyOffline => 'No connection to Spotify';

  @override
  String library_spotifyRateLimited(int seconds) {
    return 'Spotify asks to wait $seconds s';
  }

  @override
  String get library_spotifyRejected => 'Spotify rejected the key';

  @override
  String get library_srcSpotifyUnreadableDetail =>
      'Paste a YouTube link for the song instead.';

  @override
  String get library_srcSpotifyUnreadableTitle =>
      'Couldn’t read the Spotify data';

  @override
  String get library_srcTimedOutDetail =>
      'The server is taking too long to respond. Try again.';

  @override
  String get library_srcTimedOutTitle => 'Timed out';

  @override
  String get library_srcUnsupportedTitle => 'Link not supported';

  @override
  String get library_srcUpdateFailedTitle => 'Couldn’t update yt-dlp';

  @override
  String get library_stateDetailDone => 'Separated';

  @override
  String library_stateDetailFailed(String message) {
    return 'Error: $message';
  }

  @override
  String get library_stateDetailFailedUnknown => 'unknown';

  @override
  String get library_stateDetailImported => 'Imported';

  @override
  String get library_stateDetailQueued => 'Queued';

  @override
  String get library_stateDetailRunning => 'Separating';

  @override
  String get library_stateDone => 'Separated';

  @override
  String get library_stateFailed => 'Error';

  @override
  String get library_stateFailedUnknown => 'Unknown error';

  @override
  String get library_stateImported => 'Imported';

  @override
  String get library_stateQueued => 'Queued';

  @override
  String library_stateRunning(String percent) {
    return 'Separating $percent';
  }

  @override
  String get library_stemEmpty => 'empty';

  @override
  String get library_stemsNone => 'No stems yet.';

  @override
  String get library_stemsTitle => 'Stems';

  @override
  String get library_subtitle => 'Your songs.';

  @override
  String get library_swapTooltip => 'Swap title and artist';

  @override
  String get library_takeBest => 'Best take';

  @override
  String library_takeBestError(String error) {
    return 'Couldn’t mark the take as best ($error).';
  }

  @override
  String get library_takeDelete => 'Delete';

  @override
  String library_takeDeleteConfirm(String label) {
    return 'Delete $label';
  }

  @override
  String library_takeDeleteError(String error) {
    return 'Couldn’t delete the take ($error).';
  }

  @override
  String get library_takeDeleteMessage =>
      'Its folder (audio and video) will be deleted. This can’t be undone.';

  @override
  String get library_takeDeleteTitle => 'Delete take?';

  @override
  String library_takeLabel(int n, String part) {
    return 'Take $n · $part';
  }

  @override
  String get library_takeNoDuration => '–';

  @override
  String get library_takeNoVideo => 'No video';

  @override
  String library_takeNumber(int n) {
    return 'Take $n';
  }

  @override
  String library_takePunches(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count punches',
      one: '1 punch',
    );
    return '$_temp0';
  }

  @override
  String get library_takesNone => '—';

  @override
  String get library_takeView => 'View take';

  @override
  String get library_takeWithVideo => 'With video';

  @override
  String get library_title => 'Library';

  @override
  String library_trashContentsStems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stems',
      one: '1 stem',
      zero: 'its stems',
    );
    return '$_temp0';
  }

  @override
  String library_trashContentsTakes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count takes',
      one: '1 take',
    );
    return '$_temp0';
  }

  @override
  String library_trashContentsVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '1 video',
    );
    return '$_temp0';
  }

  @override
  String get library_trashDelete => 'Delete from disk';

  @override
  String library_trashMessageMac(String contents) {
    return 'It goes with the song: $contents. If it is being separated or open in Backing, it is stopped first.\nDelete from disk can’t be undone. The Trash keeps the folder until you empty it.';
  }

  @override
  String library_trashMessageWindows(String contents) {
    return 'It goes with the song: $contents. If it is being separated or open in Backing, it is stopped first.\nDelete from disk can’t be undone. The Recycle Bin keeps the folder until you empty it.';
  }

  @override
  String library_trashTitle(String title) {
    return 'Delete “$title”?';
  }

  @override
  String get library_trashToBinMac => 'Move to Trash';

  @override
  String get library_trashToBinWindows => 'Move to Recycle Bin';

  @override
  String get library_viewArtists => 'Artists';

  @override
  String get library_viewLabel => 'View';

  @override
  String get library_viewSongs => 'Songs';

  @override
  String get backingAnchor => '';

  @override
  String get tabAnchor => '';

  @override
  String get recordAnchor => '';

  @override
  String get montageAnchor => '';

  @override
  String get settingsAnchor => '';

  @override
  String get settings_lang_en => 'English';

  @override
  String get settings_lang_es => 'Español';

  @override
  String get settings_lang_label => 'Language';

  @override
  String get settings_lang_system => 'System';

  @override
  String get settings_lang_title => 'Language';

  @override
  String get settings_lib_cancel => 'Cancel';

  @override
  String get settings_lib_change => 'Change folder';

  @override
  String get settings_lib_clean => 'Clean discarded takes and stems';

  @override
  String get settings_lib_cleanTitle => 'Clean the whole library';

  @override
  String get settings_lib_folder => 'Project folder';

  @override
  String get settings_lib_moveHere => 'Move songs here';

  @override
  String settings_lib_moving(String percent) {
    return 'Moving $percent';
  }

  @override
  String get settings_lib_note =>
      'One folder per song, with its stems, takes and video.';

  @override
  String get settings_lib_pointOnly => 'Just point to this folder';

  @override
  String settings_lib_relocateMessage(String path) {
    return '“$path”: move the existing songs to the new folder or just point to it?';
  }

  @override
  String get settings_lib_title => 'Library';

  @override
  String get settings_lib_usage => 'Space used';

  @override
  String get settings_lib_workInProgress =>
      'There is work in progress. Wait for the separations to finish and change the folder again.';

  @override
  String get settings_models_delete => 'Delete';

  @override
  String get settings_models_deleteMessage =>
      'It will be downloaded again the next time you separate a song.';

  @override
  String get settings_models_deleteTitle => 'Delete the model';

  @override
  String get settings_models_download => 'Download';

  @override
  String settings_models_downloading(String percent) {
    return 'Downloading $percent';
  }

  @override
  String get settings_models_error => 'Error';

  @override
  String settings_models_installed(String size) {
    return 'Downloaded · $size';
  }

  @override
  String get settings_models_installing => 'Installing…';

  @override
  String get settings_models_note =>
      'They are downloaded the first time they are used.';

  @override
  String settings_models_pending(String size) {
    return 'Pending · $size';
  }

  @override
  String get settings_models_title => 'Models';

  @override
  String get settings_models_verifying => 'Verifying…';

  @override
  String get settings_subtitle =>
      'Set it up once and every screen uses it. It is saved in your machine profile.';

  @override
  String get settings_tabAudio => 'Audio';

  @override
  String get settings_tabLibrary => 'Library';

  @override
  String get settings_tabVideo => 'Camera & video';

  @override
  String get settings_tools_checking => 'checking…';

  @override
  String get settings_tools_embedded => 'bundled';

  @override
  String get settings_tools_note =>
      'Import from link uses yt-dlp, Deno and ffmpeg, which are bundled in the app. If YouTube changes and downloads fail, update yt-dlp.';

  @override
  String get settings_tools_revert => 'Revert to bundled version';

  @override
  String get settings_tools_title => 'External sources';

  @override
  String get settings_tools_unavailable => 'unavailable';

  @override
  String get settings_tools_update => 'Update yt-dlp';

  @override
  String get settings_tools_updated => 'up to date';

  @override
  String settings_tools_updateDone(String version) {
    return 'yt-dlp updated to $version.';
  }

  @override
  String settings_tools_upToDate(String version) {
    return 'You already have the latest version ($version).';
  }

  @override
  String get errorAnchor => '';

  @override
  String get error_unknown => 'Unknown error';
}
