{
        File: downloads.pas
        License: GPLv2
        This unit is a part of Free Manga Downloader
}

unit DownloadsManager;

{$mode delphi}

interface

uses
  Classes, SysUtils, IniFiles, baseunit, data, fgl, zip, ExtCtrls, Graphics,
  FMDThread, dateutils;

type
  TDownloadManager = class;
  TTaskThreadContainer = class;
  TTaskThread = class;

  // this class will replace the old TDownloadThread
  TDownloadThread = class(TFMDThread)
  protected
    parse        : TStringList;
    workCounter      : Cardinal;

    FSortColumn  : Cardinal;
    FAnotherURL  : String;

    // wait for changing directoet completed
    procedure   SetChangeDirectoryFalse;
    procedure   SetChangeDirectoryTrue;
    // Get download link from URL
    function    GetLinkPageFromURL(const URL: String): Boolean;
    // Get number of download link from URL
    function    GetPageNumberFromURL(const URL: String): Boolean;
    // Download page - links are from link list
    function    DownloadPage: Boolean;
    procedure   Execute; override;
    procedure   OnTag(tag: String);
    procedure   OnText(text: String);
  public
    checkStyle    : Cardinal;
    // ID of the site
    manager       : TTaskThread;

    constructor Create;
    destructor  Destroy; override;

    property    SortColumn: Cardinal read FSortColumn write FSortColumn;
    property    AnotherURL: String read FAnotherURL write FAnotherURL;
  end;

  TDownloadThreadList = TFPGList<TDownloadThread>;

  TTaskThread = class(TFMDThread)
  protected
    FAnotherURL  : String;

    procedure   CheckOut;
    procedure   CallMainFormCompressRepaint;
    procedure   CallMainFormRepaint;
    procedure   CallMainFormRepaintImm;
    procedure   Execute; override;
    procedure   Compress;
    // show notification when download completed
    procedure   ShowBaloon;
  public
    Flag: Cardinal;
    // container (for storing information)
    container  : TTaskThreadContainer;
    // download threads
    threads    : TDownloadThreadList;

    constructor Create;
    destructor  Destroy; override;
    procedure   Stop(const check: Boolean = TRUE);

    property    AnotherURL: String read FAnotherURL write FAnotherURL;
  end;

  TTaskThreadContainer = class
    // task thread of this container
    thread : TTaskThread;
    // download manager
    manager: TDownloadManager;

    downloadInfo: TDownloadInfo;

    // current link index
    currentPageNumber,
    // current chapter index
    currentDownloadChapterPtr,
    activeThreadCount,
    Status     : Cardinal;
    workCounter    : Cardinal;
    mangaSiteID: Cardinal;
    pageNumber : Cardinal;

    chapterName,
    chapterLinks,
    pageContainerLinks,
    pageLinks  : TStringList;

    constructor Create;
    destructor  Destroy; override;
  end;

  TTaskThreadContainerList = TFPGList<TTaskThreadContainer>;

  TDownloadManager = class(TObject)
  private
    FSortDirection: Boolean;
    FSortColumn   : Cardinal;
  public
    isRunningBackup,
    isFinishTaskAccessed,
    isRunningBackupDownloadedChaptersList: Boolean;

    compress,
    //
    retryConnect,
    // max. active tasks
    maxDLTasks,
    // max. download threads per task
    maxDLThreadsPerTask : Cardinal;
    // current chapterLinks which thread is processing
    containers          : TTaskThreadContainerList;

    downloadedChaptersList: TStringList;
    ini                 : TIniFile;

    // for highlight downloaded chapters
    DownloadedChapterList: TList;

   // downloadInfo        : array of TDownloadInfo;
    constructor Create;
    destructor  Destroy; override;

    procedure   BackupDownloadedChaptersList;

    procedure   Restore;
    procedure   Backup;
    procedure   SaveJobList;

    procedure   AddToDownloadedChaptersList(const ALink: String); overload;
    procedure   AddToDownloadedChaptersList(const ALink, AValue: String); overload;
    procedure   ReturnDownloadedChapters(const ALink: String);

    // Add new task to the list
    procedure   AddTask;
    // Check and active previous work-in-progress tasks
    procedure   CheckAndActiveTaskAtStartup;
    // Check and active waiting tasks
    procedure   CheckAndActiveTask(const isCheckForFMDDo: Boolean = FALSE);
    // Check if we can active another wating task or not
    function    CanActiveTask(const pos: Cardinal): Boolean;
    // Active a stopped task
    procedure   ActiveTask(const taskID: Cardinal);
    // Stop a download/wait task
    procedure   StopTask(const taskID: Cardinal; const isCheckForActive: Boolean = TRUE);
    // Stop all download/wait tasks
    procedure   StopAllTasks;
    // Stop all download task inside a task before terminate the program
    procedure   StopAllDownloadTasksForExit;
    // Mark the task as "Finished"
    procedure   FinishTask(const taskID: Cardinal);
    // Swap 2 tasks
    function    Swap(const id1, id2: Cardinal): Boolean;
    // move a task up
    function    MoveUp(const taskID: Cardinal): Boolean;
    // move a task down
    function    MoveDown(const taskID: Cardinal): Boolean;
    // Remove a task from list
    procedure   RemoveTask(const taskID: Cardinal);
    // Remove all finished tasks
    procedure   RemoveAllFinishedTasks;

    // sorting
    procedure   Sort(const AColumn: Cardinal);

    property    SortDirection: Boolean read FSortDirection write FSortDirection;
    property    SortColumn: Cardinal read FSortColumn write FSortColumn;
  end;

implementation

uses
  lazutf8classes, mainunit, HTMLParser, FastHTMLParser, HTMLUtil, LConvEncoding,
  SynaCode, FileUtil, HTTPSend, VirtualTrees;

// utility

procedure picScale(P1: TPicture; var P2: TPicture; const x, y: Integer);
var
  ARect: TRect;
begin
  P2.Clear;
  P2.BitMap.Width := X;
  P2.BitMap.Height:= Y;
  Arect:= Rect(0, 0, X, Y);
  P2.BitMap.Canvas.StretchDraw(ARect, P1.BitMap);
end;

// ----- TDownloadThread -----

procedure   TDownloadThread.OnTag(tag: String);
begin
  parse.Add(tag);
end;

procedure   TDownloadThread.OnText(text: String);
begin
  parse.Add(text);
end;

constructor TDownloadThread.Create;
begin
  isTerminated:= FALSE;
  isSuspended := TRUE;
  FreeOnTerminate:= TRUE;
  inherited Create(FALSE);
end;

destructor  TDownloadThread.Destroy;
begin
  // TODO: Need recheck
  try
   // if NOT Terminated2 then
    Dec(manager.container.activeThreadCount);
  except
  end;
  isTerminated:= TRUE;
  inherited Destroy;
end;

procedure   TDownloadThread.Execute;
var
  i: Cardinal;
begin
  while isSuspended do
    Sleep(100);
  case checkStyle of
    // get page number, and prepare number of pagelinks for save links
    CS_GETPAGENUMBER:
      begin
        GetPageNumberFromURL(manager.container.chapterLinks.Strings[manager.container.currentDownloadChapterPtr]);
        // prepare 'space' for link updater
       // if manager.container.mangaSiteID <> GEHENTAI_ID then
        if (NOT Terminated) AND
           (manager.container.pageNumber > 0) then
          for i:= 0 to manager.container.pageNumber-1 do
            manager.container.pageLinks.Add('W');
      end;
    // get page link
    CS_GETPAGELINK:
      begin
        if (NOT Terminated) then
          GetLinkPageFromURL(manager.container.chapterLinks.Strings[manager.container.currentDownloadChapterPtr]);
      end;
    // download page
    CS_DOWNLOAD:
      begin
        if (NOT Terminated) then
          DownloadPage;
      end;
  end;
  Terminate;
end;

function    TDownloadThread.GetPageNumberFromURL(const URL: String): Boolean;
var
  myParser: THTMLParser;
  Parser  : TjsFastHTMLParser;

  function GetAnimeAPageNumber: Boolean;
  var
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l), WebsiteRoots[ANIMEA_ID,1] +
                                 StringReplace(URL, '.html', '', []) +
                                 '-page-1.html',
                                 manager.container.manager.retryConnect);
    for i:= 0 to l.Count-1 do
      if (Pos('Page 1 of ', l.Strings[i])<>0) then
      begin
        manager.container.pageNumber:= StrToInt(GetString(l.Strings[i], 'Page 1 of ', '<'));
        break;
      end;
    l.Free;
  end;

  function GetMangaHerePageNumber: Boolean;
  var
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAHERE_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if GetTagName(parse.Strings[i]) = 'option' then
        begin
          j:= i;
          while GetTagName(parse.Strings[j]) = 'option' do
          begin
            Inc(manager.container.pageNumber);
            Inc(j, 4);
          end;
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetEsMangaHerePageNumber: Boolean;
  var
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[ESMANGAHERE_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 4 do
      begin
        if Pos('</select>', parse.Strings[i]) > 0 then
        begin
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(parse.Strings[i-3])));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetSubMangaPageNumber: Boolean;
  var
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[SUBMANGA_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 3 do
      begin
        if Pos('</select>', parse.Strings[i]) > 0 then
        begin
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(parse.Strings[i-2])));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetAnimeExtremistPageNumber: Boolean;
  var
    i, j: Cardinal;
    l   : TStringList;
    s   : String;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= StringReplace(WebsiteRoots[ANIMEEXTREMIST_ID,1] + URL, '.html', '', []) + '-1.html';
    Result:= GetPage(TObject(l),
                     StringReplace(WebsiteRoots[ANIMEEXTREMIST_ID,1] + URL, '.html', '', []) + '-1.html',
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('</select>', parse.Strings[i]) > 0 then
        begin
          manager.container.pageNumber:= StrToInt(GetString(TrimLeft(TrimRight(parse.Strings[i-3]+'~!@')), 'Pagina ', '~!@'));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaInnPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAINN_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 1;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('Previous', parse.Strings[i]) <> 0 then
         // if Pos('Page', parse.Strings[i+2]) <> 0 then
        begin
          j:= i+7;
          s:= parse.Strings[j];
          while GetTagName(parse.Strings[j]) = 'option' do
          begin
            Inc(manager.container.pageNumber);
            Inc(j, 3);
          end;
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetOurMangaPageNumber: Boolean;
  // OurManga is a lot different than other site
  var
    isExtractpageContainerLinks: Boolean = FALSE;
    correctURL,
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    // pass 1: Find correct chapter
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[OURMANGA_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 1;
      for i:= 0 to parse.Count-1 do
      begin
        if (GetTagName(parse.Strings[i]) = 'a') AND
           (Pos(WebsiteRoots[OURMANGA_ID,1] + URL, parse.Strings[i]) <> 0) then
          correctURL:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'href='));
      end;
    end;
    parse.Clear;
    l.Clear;

    // pass 2: Find number of pages

    Result:= GetPage(TObject(l),
                     correctURL,
                     manager.container.manager.retryConnect);
    manager.container.pageContainerLinks.Clear;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if NOT isExtractpageContainerLinks then
        begin
          if (GetTagName(parse.Strings[i]) = 'select') AND
             (GetAttributeValue(GetTagAttribute(parse.Strings[i], 'name=')) = 'page') then
            isExtractpageContainerLinks:= TRUE;
        end
        else
        begin
          if (GetTagName(parse.Strings[i]) = 'option') then
          begin
            manager.container.pageContainerLinks.Add(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'value=')));
            Inc(manager.container.pageNumber);
          end
          else
          if Pos('</select>', parse.Strings[i])<>0 then
            break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetBatotoPageNumber: Boolean;
  var
    isGoOn: Boolean = FALSE;
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;

    parse.Clear;
    l.Clear;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[BATOTO_ID,1] + URL + '/1',
                     manager.container.manager.retryConnect);

    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.SlowExec;
    Parser.Free;

    if parse.Count > 0 then
    begin
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('page_select', parse.Strings[i])<>0) then
        begin
          isGoOn:= TRUE;
          break;
        end;
      end;
    end;

    if NOT isGoOn then
    begin
      manager.container.pageNumber:= 1;
      parse.Free;
      l.Free;
      exit;
    end;

   // parse.Add(WebsiteRoots[BATOTO_ID,1] + URL + '/1');
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('page_select', parse.Strings[i]) <> 0 then
         // if Pos('Page', parse.Strings[i+2]) <> 0 then
        begin
          j:= i+2;
          s:= parse.Strings[j];
          while GetTagName(parse.Strings[j]) = 'option' do
          begin
            Inc(manager.container.pageNumber);
            Inc(j, 3);
          end;
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetHentai2ReadPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     HENTAI2READ_ROOT + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (GetTagName(parse.Strings[i]) = 'select') AND
           (GetAttributeValue(GetTagAttribute(parse.Strings[i], 'class='))='cbo_wpm_pag') then
        begin
          j:= i+1;
          while GetTagName(parse.Strings[j]) = 'option' do
          begin
            Inc(manager.container.pageNumber);
            Inc(j, 3);
          end;
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaReaderPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAREADER_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    s:= WebsiteRoots[MANGAREADER_ID,1] + URL;
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('</select>', parse.Strings[i])>0) AND
           (Pos('</div>', parse.Strings[i+2])>0) then
        begin
          s:= parse.Strings[i+1];
          Delete(s, Pos(' of ', s), 4);
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaParkPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAPARK_ID,1] + URL + '1',
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('1 of ', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i];
          Delete(s, Pos('1 of ', s), 5);
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaFoxPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(URL + '/1.html');
    if Pos(WebsiteRoots[MANGAFOX_ID,1], s) = 0 then
      s:= WebsiteRoots[MANGAFOX_ID,1] + s;
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('option value="0"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-3];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetStarkanaPageNumber: Boolean;
  var
    s    : String;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[STARKANA_ID,1] + URL);
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 5 do
      begin
        if (Pos('</option>', parse.Strings[i])>0) then
        begin
          s:= TrimLeft(TrimRight(parse.Strings[i-1]));
          manager.container.pageNumber:= StrToInt(s);
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetEatMangaPageNumber: Boolean;
  var
    s    : String;
    count: Cardinal = 0;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[EATMANGA_ID,1] + URL);
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('</select>', parse.Strings[i])>0) then
          if count > 0 then
          begin
            s:= parse.Strings[i-2];
            manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
            break;
          end
          else
            Inc(count);
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaPandaPageNumber: Boolean;
  var
    s    : String;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAPANDA_ID,1] + URL);
    if (Pos('.html', URL) > 0) AND (Pos(SEPERATOR2, URL) > 0) then
      s:= StringReplace(s, SEPERATOR2, '-1/', []);
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 1 to parse.Count-1 do
      begin
        if (Pos(' of ', parse.Strings[i])>0) AND
           (Pos('select', parse.Strings[i-1])>0) then
        begin
          s:= GetString(parse.Strings[i]+'~!@', ' of ', '~!@');
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaGoPageNumber: Boolean;
  var
    s    : String;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    if (Pos('http://', URL) > 0) then
      s:= DecodeUrl(URL + '1/')
    else
      s:= DecodeUrl(WebsiteRoots[MANGAGO_ID,1] + URL + '1/');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 5 do
      begin
        if (Pos('class="clear gap"', parse.Strings[i])>0) then
        begin
          s:= TrimLeft(TrimRight(parse.Strings[i-5]));
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetRedHawkScansPageNumber: Boolean;
  var
    s    : String;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[REDHAWKSCANS_ID,1] + URL +'page/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 1 to parse.Count-1 do
      begin
        if (Pos('class="topbar_right"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i+4];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetS2scanPageNumber: Boolean;
  var
    s    : String;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[S2SCAN_ID,1] + URL +'page/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 1 to parse.Count-1 do
      begin
        if (Pos('class="topbar_right"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i+4];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(GetString('~!@'+s, '~!@', ' '))));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetEGScansPageNumber: Boolean;
  var
    s    : String;
    i, j : Cardinal;
    l    : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[EGSCANS_ID,1] + URL +'/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 2 do
      begin
        if (Pos('</span>', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-4];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(GetString(s+' ', 'of ', ' '))));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaTradersPageNumber: Boolean;
  var
    isStartGetPageNumber: Boolean = FALSE;
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGATRADERS_ID,1] + URL,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (NOT isStartGetPageNumber) AND
           (Pos('option value="1"  selected="selected"', parse.Strings[i]) > 0) then
          isStartGetPageNumber:= TRUE;
        if (isStartGetPageNumber) AND
           (Pos('</option>', parse.Strings[i])>0) then
          Inc(manager.container.pageNumber);
        if (isStartGetPageNumber) AND
           (Pos('</select>', parse.Strings[i])>0) then
          break;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaStreamPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(MANGASTREAM_ROOT2 + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('Last Page (', parse.Strings[i])>0) then
        begin
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(GetString(parse.Strings[i], 'Last Page (', ')'))));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetKomikidPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[KOMIKID_ID,1] + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('title="Next Page"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-6];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetPecintaKomikPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[PECINTAKOMIK_ID,1] + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 5 do
      begin
        if (Pos('</option>', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-1];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;
  
 function GetPururinPageNumber: Boolean;
  var
    s   : String;
    i,g,j: Cardinal;
    l   : TStringList;
    isStartGetPageNumber: Boolean = FALSE;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
        s:= StringReplace(URL, '_1.html', '.html', []);
		s:= StringReplace(s, '/view/', '/gallery/', []);
		s:= DecodeUrl(StringReplace(s, '/00/', '/', []));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('class="square"', parse.Strings[i])>0) then
          isStartGetPageNumber:= TRUE;

        if (isStartGetPageNumber) AND
           (Pos('class="square"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i+1];
		  g:= length(s);
          Delete(s,g-10,g-3);
          Delete(s,1,9);
		  g:= StrToInt(s);
          manager.container.pageNumber:= g;
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetHugeMangaPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[HUGEMANGA_ID,1] + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 5 do
      begin
        if (Pos('</option>', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-2];
          manager.container.pageNumber:= StrToInt(GetAttributeValue(GetTagAttribute(s, 'value=')));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetAnimeStoryPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    if Pos('http://', URL) = 0 then
      s:= DecodeUrl(WebsiteRoots[ANIMESTORY_ID,1] + URL + '1')
    else
      s:= DecodeUrl(URL + '1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 5 do
      begin
        if (Pos('data-page=', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i];
          manager.container.pageNumber:= StrToInt(GetAttributeValue(GetTagAttribute(s, 'data-page=')));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetTurkcraftPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[TURKCRAFT_ID,1] + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('title="Next Page"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-5];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaVadisiPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAVADISI_ID,1] + MANGAVADISI_BROWSER + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('title="Sonraki Sayfa"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-6];
          manager.container.pageNumber:= StrToInt(GetString(s, '"', '"'));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaFramePageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAFRAME_ID,1] + URL + '1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('class="divider"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-8];
          manager.container.pageNumber:= StrToInt(GetString(s, '/page/', '"'));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaArPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= WebsiteRoots[MANGAAR_ID,1] + URL + '/1';
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);

    // convert charset
    l.Text:= CP1256ToUTF8(l.Text);

    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('</select>', parse.Strings[i])>0) then
        begin
          s:= TrimLeft(TrimRight(parse.Strings[i-3]));
          manager.container.pageNumber:= StrToInt(s);
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaAePageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAAE_ID,1] + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= parse.Count-1 downto 2 do
      begin
        if (Pos('</select>', parse.Strings[i])>0) then
        begin
          s:= TrimLeft(TrimRight(parse.Strings[i-3]));
          manager.container.pageNumber:= StrToInt(s);
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;
     //mangacow page number
 function GetMangaCowPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
    isStartGetPageNumber: Boolean = FALSE;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGACOW_ID,1] + URL + '1/');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('class="cbo_wpm_pag"', parse.Strings[i])>0) then
          isStartGetPageNumber:= TRUE;

        if (isStartGetPageNumber) AND
           (Pos('</select>', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-3];
          manager.container.pageNumber:= StrToInt(GetAttributeValue(GetTagAttribute(s, 'value=')));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetSenMangaPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
    isStartGetPageNumber: Boolean = FALSE;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[SENMANGA_ID,1] + URL + '1/');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('name="page"', parse.Strings[i])>0) then
          isStartGetPageNumber:= TRUE;

        if (isStartGetPageNumber) AND
           (Pos('</select>', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-3];
          manager.container.pageNumber:= StrToInt(GetAttributeValue(GetTagAttribute(s, 'value=')));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaEdenPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    if manager.container.mangaSiteID = MANGAEDEN_ID then
      s:= DecodeUrl(WebsiteRoots[MANGAEDEN_ID,1] + URL + '1/')
    else
      s:= DecodeUrl(WebsiteRoots[PERVEDEN_ID,1] + URL + '1/');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('span class="next"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-3];
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;
  
    function GetKivmangaPageNumber: Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[KIVMANGA_ID,1] + URL + '/1');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('title="Next Page"', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i-6];
          manager.container.pageNumber:= StrToInt(GetString(s, '"', '"'));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetGEHentaiPageNumber(const lURL: String; const isGetLinkPage: Boolean): Boolean;
  var
    s   : String;
    i, j: Cardinal;
    l   : TStringList;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;
    Result:= gehGetPage(TObject(l),
                        URL,
                        manager.container.manager.retryConnect, lURL);
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageNumber:= 0;
      for i:= 0 to parse.Count-1 do
      begin
        if (isGetLinkPage) AND (Pos(' @ ', parse.Strings[i])>0) then
        begin
          s:= GetString(' '+parse.Strings[i], ' ', ' @ ');
          manager.container.pageNumber:= StrToInt(TrimLeft(TrimRight(s)));
        end;
        if Pos('background:transparent url', parse.Strings[i])>0 then
        begin
          manager.anotherURL:= GetAttributeValue(GetTagAttribute(parse.Strings[i+1], 'href='));
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
    Sleep(300);
  end;

var
  i: Cardinal;

begin
  manager.container.pageNumber:= 0;
  if manager.container.mangaSiteID = ANIMEA_ID then
    Result:= GetAnimeAPageNumber
  else
  if manager.container.mangaSiteID = MANGAHERE_ID then
    Result:= GetMangaHerePageNumber
  else
  if manager.container.mangaSiteID = MANGAINN_ID then
    Result:= GetMangaInnPageNumber
  else
  if manager.container.mangaSiteID = BATOTO_ID then
    Result:= GetBatotoPageNumber
  else
  if manager.container.mangaSiteID = MANGAFOX_ID then
    Result:= GetMangaFoxPageNumber
  else
  if manager.container.mangaSiteID = MANGAREADER_ID then
    Result:= GetMangaReaderPageNumber
  else
  if manager.container.mangaSiteID = MANGATRADERS_ID then
    Result:= GetMangaTradersPageNumber
  else
  if manager.container.mangaSiteID = STARKANA_ID then
    Result:= GetStarkanaPageNumber
  else
  if manager.container.mangaSiteID = EATMANGA_ID then
    Result:= GetEatMangaPageNumber
  else
  if manager.container.mangaSiteID = MANGAPANDA_ID then
    Result:= GetMangaPandaPageNumber
  else
  if manager.container.mangaSiteID = MANGAGO_ID then
    Result:= GetMangaGoPageNumber
  else
  if manager.container.mangaSiteID = MANGASTREAM_ID then
    Result:= GetMangaStreamPageNumber
  else
  if manager.container.mangaSiteID = REDHAWKSCANS_ID then
    Result:= GetRedHawkScansPageNumber
  else
  if manager.container.mangaSiteID = S2SCAN_ID then
    Result:= GetS2scanPageNumber
  else
  if manager.container.mangaSiteID = ESMANGAHERE_ID then
    Result:= GetEsMangaHerePageNumber
  else
  if manager.container.mangaSiteID = SUBMANGA_ID then
    Result:= GetSubMangaPageNumber
  else
  if manager.container.mangaSiteID = ANIMEEXTREMIST_ID then
    Result:= GetAnimeExtremistPageNumber
  else
  if manager.container.mangaSiteID = KOMIKID_ID then
    Result:= GetKomikidPageNumber
  else
  if manager.container.mangaSiteID = PECINTAKOMIK_ID then
    Result:= GetPecintaKomikPageNumber
  else
  if manager.container.mangaSiteID = PURURIN_ID then
    Result:= GetPururinPageNumber
  else
  if manager.container.mangaSiteID = HUGEMANGA_ID then
    Result:= GetHugeMangaPageNumber
  else
  if manager.container.mangaSiteID = ANIMESTORY_ID then
    Result:= GetAnimeStoryPageNumber
  else
  if manager.container.mangaSiteID = TURKCRAFT_ID then
    Result:= GetTurkcraftPageNumber
  else
  if manager.container.mangaSiteID = MANGAVADISI_ID then
    Result:= GetMangaVadisiPageNumber
  else
  if manager.container.mangaSiteID = MANGAFRAME_ID then
    Result:= GetMangaFramePageNumber
  else
  if manager.container.mangaSiteID = MANGAAR_ID then
    Result:= GetMangaArPageNumber
  else
  if manager.container.mangaSiteID = MANGAAE_ID then
    Result:= GetMangaAePageNumber
  else
  if manager.container.mangaSiteID = MANGACOW_ID then
    Result:= GetMangaCowPageNumber
  else
  if manager.container.mangaSiteID = SENMANGA_ID then
    Result:= GetSenMangaPageNumber
  else
  if (manager.container.mangaSiteID = MANGAEDEN_ID) OR
     (manager.container.mangaSiteID = PERVEDEN_ID) then
    Result:= GetMangaEdenPageNumber
  else
  if manager.container.mangaSiteID = KIVMANGA_ID then
    Result:= GetKivmangaPageNumber
  else
  if manager.container.mangaSiteID = GEHENTAI_ID then
  begin
    Result:= GetGEHentaiPageNumber('', TRUE);
  end
  else
  if (manager.container.mangaSiteID = KISSMANGA_ID) OR
     (manager.container.mangaSiteID = BLOGTRUYEN_ID) OR
     (manager.container.mangaSiteID = MANGAPARK_ID) OR
     (manager.container.mangaSiteID = MANGA24H_ID) OR
     (manager.container.mangaSiteID = VNSHARING_ID) OR
     (manager.container.mangaSiteID = MABUNS_ID) OR
     (manager.container.mangaSiteID = EGSCANS_ID) OR
	 (manager.container.mangaSiteID = PURURIN_ID) OR
     (manager.container.mangaSiteID = MANGAESTA_ID) OR
     (manager.container.mangaSiteID = TRUYEN18_ID) OR
     (manager.container.mangaSiteID = TRUYENTRANHTUAN_ID) OR
     (manager.container.mangaSiteID = SCANMANGA_ID) OR
     (manager.container.mangaSiteID = FAKKU_ID) OR
	 (manager.container.mangaSiteID = MANGACAN_ID) OR
     (manager.container.mangaSiteID = CENTRALDEMANGAS_ID) then
  begin
    // all of the page links are in a html page
    Result:= TRUE;
    manager.container.pageNumber:= 1;
  end
  else
  if manager.container.mangaSiteID = HENTAI2READ_ID then
    Result:= GetHentai2ReadPageNumber;
end;

function    TDownloadThread.GetLinkPageFromURL(const URL: String): Boolean;
var
  myParser: THTMLParser;
  Parser  : TjsFastHTMLParser;

  function GetAnimeALinkPage: Boolean;
  var
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[ANIMEA_ID,1] +
                     StringReplace(URL, '.html', '', []) +
                     '-page-'+IntToStr(workCounter+1)+'.html',
                     manager.container.manager.retryConnect);
    for i:= 0 to l.Count-1 do
      if (Pos('class="mangaimg', l.Strings[i])<>0) then
      begin
        manager.container.pageLinks.Strings[workCounter]:= GetString(l.Strings[i], '<img src="', '"');
        break;
      end;
    l.Free;
  end;

  function GetMangaHereLinkPage: Boolean;
  var
    c: Char;
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if workCounter > 0 then
      Result:= GetPage(TObject(l),
                       WebsiteRoots[MANGAHERE_ID,1] + URL + IntToStr(workCounter+1)+'.html',
                       manager.container.manager.retryConnect)
    else
      Result:= GetPage(TObject(l),
                       WebsiteRoots[MANGAHERE_ID,1] + URL,
                       manager.container.manager.retryConnect);
    parse:= TStringList.Create;

    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        for c:= 'a' to 'z' do
          if (Pos('http://'+c+'.mhcdn.net/store/', parse.Strings[i])<>0) then
          begin
            manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
            parse.Free;
            l.Free;
            exit;
          end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetEsMangaHereLinkPage: Boolean;
  var
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if workCounter > 0 then
      Result:= GetPage(TObject(l),
                       WebsiteRoots[ESMANGAHERE_ID,1] + URL + IntToStr(workCounter+1)+'.html',
                       manager.container.manager.retryConnect)
    else
      Result:= GetPage(TObject(l),
                       WebsiteRoots[ESMANGAHERE_ID,1] + URL,
                       manager.container.manager.retryConnect);
    parse:= TStringList.Create;

    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="read_img"', parse.Strings[i])<>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i+6], 'src='));
          parse.Free;
          l.Free;
          exit;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaInnLinkPage: Boolean;
  var
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAINN_ID,1] + URL + '/page_'+IntToStr(workCounter+1),
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if GetTagName(parse.Strings[i]) = 'img' then
          if GetAttributeValue(GetTagAttribute(parse.Strings[i], 'id='))='imgPage' then
          begin
            manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
            break;
          end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetOurMangaLinkPage: Boolean;
  var
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[OURMANGA_ID,1] + URL + '/' + manager.container.pageContainerLinks.Strings[workCounter],
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (GetTagName(parse.Strings[i]) = 'div') AND
           (GetAttributeValue(GetTagAttribute(parse.Strings[i], 'class=')) = 'prev_next_top') then
        begin
          j:= i;
          repeat
            Dec(j);
            if GetTagName(parse.Strings[j]) = 'img' then
            begin
              manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[j], 'src='));
              parse.Free;
              l.Free;
              exit;
            end;
          until j = 0;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetKissMangaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[KISSMANGA_ID,1] + URL,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('lstImages.push("', parse.Strings[i]) > 0 then
        begin
          s:= parse.Strings[i];
          repeat
            j:= Pos('lstImages.push("', s);
            manager.container.pageLinks.Add(EncodeUrl(GetString(s, 'lstImages.push("', '");')));
            Delete(s, Pos('lstImages.push("', s), 16);
            j:= Pos('lstImages.push("', s);
          until j = 0;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetBatotoLinkPage: Boolean;
  var
    isGoOn: Boolean = FALSE;
    i: Cardinal;
    l: TStringList;
    s: String;
  begin
    l:= TStringList.Create;
    parse:= TStringList.Create;

    parse.Clear;
    l.Clear;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[BATOTO_ID,1] + URL + '/'+IntToStr(workCounter+1),
                     manager.container.manager.retryConnect);

    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.SlowExec;
    Parser.Free;

    if parse.Count > 0 then
    begin
      for i:= 0 to parse.Count-1 do
      begin
        if (Pos('page_select', parse.Strings[i])<>0) then
        begin
          isGoOn:= TRUE;
          break;
        end;
      end;
    end;

    case isGoOn of
      TRUE:
        begin
          for i:= 0 to parse.Count-1 do
            if GetTagName(parse.Strings[i]) = 'img' then
              if (Pos('batoto.net/comics', parse.Strings[i])>0) AND
                 (Pos('z-index: 1003', parse.Strings[i])>0) then
              begin
                manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
                break;
              end;
        end;
      FALSE:
        begin
          manager.container.pageLinks.Clear;
          for i:= 0 to parse.Count-1 do
            if GetTagName(parse.Strings[i]) = 'img' then
              if (Pos('<br/>', parse.Strings[i+1])>0) then
              begin
                manager.container.pageLinks.Add(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
              end;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetManga24hLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGA24H_ID,1] + URL,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if (GetTagName(parse.Strings[i]) = 'img') AND
           (Pos('style="border:3px', parse.Strings[i])<>0) then
          // (GetAttributeValue(GetTagAttribute(parse.Strings[i], 'class=')) = 'm_picture') then
        begin
          manager.container.pageLinks.Add(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetVnSharingLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[VNSHARING_ID,1] + URL,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('lstImages.push("', parse.Strings[i]) > 0 then
        begin
          s:= parse.Strings[i];
          repeat
            j:= Pos('lstImages.push("', s);
            manager.container.pageLinks.Add(EncodeUrl(GetString(s, 'lstImages.push("', '");')));
            Delete(s, Pos('lstImages.push("', s), 16);
            j:= Pos('lstImages.push("', s);
          until j = 0;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetHentai2ReadLinkPage: Boolean;
  var
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     HENTAI2READ_ROOT + URL + IntToStr(workCounter+1)+'/',
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (GetTagName(parse.Strings[i]) = 'img') AND
           (GetAttributeValue(GetTagAttribute(parse.Strings[i], 'id='))='img_mng_enl') then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetFakkuLinkPage: Boolean;
  var
    i, j  : Cardinal;
    l     : TStringList;
    imgURL: String;
  begin
    l:= TStringList.Create;
    // get number of pages
    Result:= GetPage(TObject(l),
                     WebsiteRoots[FAKKU_ID,1] + StringReplace(URL, '/read', '', []){ + '#page' + IntToStr(workCounter+1)},
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    j:= 0;
    if parse.Count>0 then
    begin
      i:= 0;
      manager.container.pageLinks.Clear;
      while i < parse.Count-1 do
      begin
        if (Pos('favorites', parse.Strings[i])>0) AND
           (Pos('pages', parse.Strings[i+4])>0) then
        begin
          j:= StrToInt(TrimRight(TrimLeft(parse.Strings[i+2])));
          break;
        end;
        Inc(i);
      end;
    end;
    // get link pages
    l.Clear;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[FAKKU_ID,1] + URL + '#page' + IntToStr(workCounter+1),
                     manager.container.manager.retryConnect);
    parse.Clear;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      i:= 0;
      manager.container.pageLinks.Clear;
      while i < parse.Count-1 do
      begin
        if (Pos('return ''http://c.fakku.net/', parse.Strings[i])>0) then
        begin
        //  manager.container.pageLinks.Strings[workCounter]:=
          imgURL:= 'http://c.fakku.net/' + GetString(parse.Strings[i], '''http://c.fakku.net/', '''');
          break;
        end
        else
        if (Pos('return ''http://t.fakku.net/', parse.Strings[i])>0) then
        begin
        //  manager.container.pageLinks.Strings[workCounter]:=
          imgURL:= 'http://t.fakku.net/' + GetString(parse.Strings[i], '''http://t.fakku.net/', '''');
          break;
        end
        else
        if (Pos('return ''http://cdn.fakku.net/', parse.Strings[i])>0) then
        begin
        //  manager.container.pageLinks.Strings[workCounter]:=
          imgURL:= 'http://cdn.fakku.net/' + GetString(parse.Strings[i], '''http://cdn.fakku.net/', '''');
          break;
        end;
        Inc(i);
      end;
    end;
    // build page files
    for i:= 1 to j do
    begin
     // s:= imgURL + Format('%3.3d.jpg', [i]);
      manager.container.pageLinks.Add(imgURL + Format('%3.3d.jpg', [i]));
    end;
    parse.Free;
    l.Free;
  end;

  function GetTruyen18LinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     TRUYEN18_ROOT + URL,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('[IMG]http://', parse.Strings[i]) > 0 then
        begin
          s:= parse.Strings[i];
          repeat
            j:= Pos('[IMG]http://', s);
            manager.container.pageLinks.Add(EncodeUrl(GetString(s, '[IMG]', '[/IMG];')));
            Delete(s, Pos('[IMG]http://', s), 16);
            j:= Pos('[IMG]http://', s);
          until j = 0;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaReaderLinkPage: Boolean;
  var
    realURL,
    s: String;
    j,
    i: Cardinal;
    l: TStringList;

    procedure  BreakURL;
    var
      isSlashed: Boolean = FALSE;
      i,
      oldI     : Cardinal;
    begin
      if Pos('.html', URL) = 0 then
      begin
        realURL:= URL + '/' + IntToStr(workCounter+1);
        exit;
      end;
      i:= 2;
      realURL:= '/';
      while i <= Length(URL) do
      begin
        if (NOT isSlashed) AND (URL[i] = '/') then
        begin
          isSlashed:= TRUE;
          oldI:= i;
          for i:= i-1 downto 1 do
          begin
            if URL[i] <> '-' then
            begin
              SetLength(realURL, Length(realURL)-1);
            end
            else
            begin
              realURL:= realURL + IntToStr(workCounter+1);
              break;
            end;
          end;
          i:= oldI;
         // realURL:= realURL + '/';
        end
        else
        begin
          realURL:= realURL + URL[i];
          Inc(i);
        end;
      end;
    end;

  begin
    l:= TStringList.Create;
    BreakURL;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAREADER_ID,1] + realURL,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
     // manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if GetTagName(parse.Strings[i]) = 'img' then
        begin
          if //(Pos(realURL, parse.Strings[i])>0) AND
             (Pos('alt=', parse.Strings[i])>0) then
          begin
            manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
            break;
          end;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaParkLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[MANGAPARK_ID,1] + URL + 'all',//IntToStr(workCounter+1),
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
       // if GetTagName(parse.Strings[i]) = 'img' then
        if (Pos('a target="_blank"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Add(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'href=')));
      //    break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaFoxLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(URL + '/' + IntToStr(workCounter+1) + '.html');
    if Pos(WebsiteRoots[MANGAFOX_ID,1], s) = 0 then
      s:= WebsiteRoots[MANGAFOX_ID,1] + s;
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('onclick="return enlarge()"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i+1], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetStarkanaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[STARKANA_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= parse.Count-1 downto 5 do
        if (Pos('style="cursor: pointer;"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetEatMangaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[EATMANGA_ID,1] + URL + 'page-' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('<div id="prefetchimg"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i-1], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetSubMangaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[SUBMANGA_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('type="text/javascript"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i-3], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetAnimeExtremistLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(StringReplace(WebsiteRoots[ANIMEEXTREMIST_ID,1] + URL, '.html', '', []) + '-' + IntToStr(workCounter+1) + '.html');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('id="photo"', parse.Strings[i])>0) then
        begin
          s:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaPandaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;

    if (Pos('.html', URL) > 0) AND (Pos(SEPERATOR2, URL) > 0) then
    begin
      s:= DecodeUrl(WebsiteRoots[MANGAPANDA_ID,1] + URL);
      s:= StringReplace(s, SEPERATOR2, '-' + IntToStr(workCounter+1) + '/', [])
    end
    else
      s:= DecodeUrl(WebsiteRoots[MANGAPANDA_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('"imgholder"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i+2], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaGoLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;

    if (Pos('http://', URL) > 0) then
      s:= DecodeUrl(URL + IntToStr(workCounter+1) + '/')
    else
      s:= DecodeUrl(WebsiteRoots[MANGAGO_ID,1] + URL + IntToStr(workCounter+1) + '/');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('imgReady(''', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= (GetString(parse.Strings[i], 'imgReady(''', ''','));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetRedHawkScansLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;

    s:= DecodeUrl(WebsiteRoots[REDHAWKSCANS_ID,1] + URL + 'page/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="open"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetS2scanLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;

    s:= DecodeUrl(WebsiteRoots[S2SCAN_ID,1] + URL + 'page/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="open"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetEGScansLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;

    s:= DecodeUrl(WebsiteRoots[EGSCANS_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
        if (Pos('<img ondragstart', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Add(WebsiteRoots[EGSCANS_ID,1] + '/' + EncodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='))));
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaStreamLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(MANGASTREAM_ROOT2 + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('id="manga-page"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetTruyenTranhTuanLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[TRUYENTRANHTUAN_ID,1] + URL + 'doc-truyen/',
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('var slides2=["', parse.Strings[i]) > 0 then
        begin
          s:= parse.Strings[i];
          repeat
            j:= Pos('"/manga/', s);
            manager.container.pageLinks.Add(EncodeUrl(WebsiteRoots[TRUYENTRANHTUAN_ID,1] + '/manga/' + GetString(s, '"/manga/', '"')));
            Delete(s, Pos('"/manga/', s), 10);
            j:= Pos('"/manga/', s);
          until j = 0;
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetBlogTruyenLinkPage: Boolean;
  var
    isExtrackLink: Boolean = FALSE;
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     WebsiteRoots[BLOGTRUYEN_ID,1] + URL,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if NOT (isExtrackLink) AND (Pos('<div id="noidungchuong">', parse.Strings[i]) > 0) then
          isExtrackLink:= TRUE;
        if (isExtrackLink) AND (GetTagName(parse.Strings[i]) = 'img') then
          manager.container.pageLinks.Add(EncodeUrl(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='))))
        else
        if (isExtrackLink) AND (Pos('</div>', parse.Strings[i])>0) then
          break;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetKomikidLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[KOMIKID_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="lazyload_ad"', parse.Strings[i])>0) then
        begin
          s:= '';
          s:= GetAttributeValue(GetTagAttribute(parse.Strings[i-8], 'src='));
          if s = '' then
            s:= GetAttributeValue(GetTagAttribute(parse.Strings[i-6], 'src='));
          if Pos('http://', s) = 0 then
            s:= WebsiteRoots[KOMIKID_ID,1] + KOMIKID_BROWSER + s;
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(s);
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetPecintaKomikLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[PECINTAKOMIK_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('mangas/', parse.Strings[i])>0) then
        begin
          s:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          if Pos('/manga/', s) = 0 then
            s:= WebsiteRoots[PECINTAKOMIK_ID,1] + '/manga/' + s
          else
            s:= WebsiteRoots[PECINTAKOMIK_ID,1] + PECINTAKOMIK_BROWSER + s;
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(s);
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMabunsLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if Pos('http://', URL) = 0 then
      s:= WebsiteRoots[MABUNS_ID,1] + URL
    else
      s:= URL;
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('addpage(''', parse.Strings[i]) > 0 then
        begin
          s:= parse.Strings[i];
          s:= StringReplace(s, 'https://', 'http://', [rfReplaceAll]);
          repeat
            j:= Pos('addpage(''', s);
            if Pos('googleusercontent', s) > 0 then
              manager.container.pageLinks.Add(EncodeUrl(GetString(s, 'addpage(''', ''',')))
            else
              manager.container.pageLinks.Add(EncodeUrl(GetString(s, 'addpage(''', ');')));
            Delete(s, Pos('addpage(''', s), 16);
            j:= Pos('addpage(''', s);
          until j = 0;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaEstaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if Pos('http://', URL) = 0 then
      s:= WebsiteRoots[MANGAESTA_ID,1] + URL
    else
      s:= URL;
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('addpage(''', parse.Strings[i]) > 0 then
        begin
          s:= parse.Strings[i];
          s:= StringReplace(s, 'https://', 'http://', [rfReplaceAll]);
          repeat
            j:= Pos('addpage(''', s);
            if Pos('googleusercontent', s) > 0 then
              manager.container.pageLinks.Add(EncodeUrl(GetString(s, 'addpage(''', ''',')))
            else
              manager.container.pageLinks.Add(EncodeUrl(GetString(s, 'addpage(''', ');')));
            Delete(s, Pos('addpage(''', s), 16);
            j:= Pos('addpage(''', s);
          until j = 0;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;
  
  function GetPururinLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
	  s:= StringReplace(URL, '_1.html', '_', []);
      s:= DecodeUrl(StringReplace(s, '/00', '/0' + IntToStr(workCounter+0), []) + IntToStr(workCounter+1) + '.html');
    Result:= GetPage(TObject(l),
	                 s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= parse.Count-1 downto 4 do
        if (Pos('class="b"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(WebsiteRoots[PURURIN_ID,1] + GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetHugeMangaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[HUGEMANGA_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="picture"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(WebsiteRoots[HUGEMANGA_ID,1] + HUGEMANGA_BROWSER + GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetAnimeStoryLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[ANIMESTORY_ID,1] + URL + IntToStr(workCounter+1));
    if Pos('http://', URL) = 0 then
      s:= DecodeUrl(WebsiteRoots[ANIMESTORY_ID,1] + URL + IntToStr(workCounter+1))
    else
      s:= DecodeUrl(URL + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('id="chpimg"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= DecodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetScanMangaLinkPage: Boolean;
  var
    s2,
    stub,
    tmp,
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if Pos('http://', URL) = 0 then
      s:= DecodeUrl(WebsiteRoots[SCANMANGA_ID,1] + URL)
    else
      s:= DecodeUrl(URL);
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    manager.container.pageLinks.Clear;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('''+u[id_page]', parse.Strings[i])>0) then
        begin
          stub:= 'http' + GetString(parse.Strings[i], '$(''#image_lel'').attr(''src'',''http', '''+u[id_page]');
          break;
        end;
    end;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('var u = new Array', parse.Strings[i])>0) then
        begin
          s:= parse.Strings[i];
          repeat
            tmp:= GetString(s, ';u[', ']="');
            s:= StringReplace(s, ';u[' +tmp+ ']="', '~!@<>', []);
            tmp:= stub + GetString(s, '~!@<>', '";n[');
            //s2:= EncodeUrl(stub + GetString(s, '~!@<>', '";n'));
            manager.container.pageLinks.Add((stub + GetString(s, '~!@<>', '";n')));
            s:= StringReplace(s, '~!@<>', '', []);
            s:= StringReplace(s, '";n[', '', []);
            j:= Pos('";n[', s);
          until j = 0;
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetTurkcraftLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[TURKCRAFT_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="picture"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(WebsiteRoots[TURKCRAFT_ID,1] + TURKCRAFT_BROWSER + GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaVadisiLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAVADISI_ID,1] + MANGAVADISI_BROWSER + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="picture"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(WebsiteRoots[MANGAVADISI_ID,1] + MANGAVADISI_BROWSER + GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaFrameLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAFRAME_ID,1] + URL + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="open"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaAeLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[MANGAAE_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('id="picture_url"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaArLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= WebsiteRoots[MANGAAR_ID,1] + URL + '/' + IntToStr(workCounter+1);
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);

    // convert charset
    l.Text:= CP1256ToUTF8(l.Text);

    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('id="PagePhoto"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i+2], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetCentralDeMangasLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= EncodeUrl(WebsiteRoots[CENTRALDEMANGAS_ID,1] + URL); // + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
    if parse.Count>0 then
    begin
      manager.container.pageLinks.Clear;
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('var pages = ', parse.Strings[i]) > 0 then
        begin
          s:= StringReplace(parse.Strings[i], '\/', '/', [rfReplaceAll]);
          repeat
            j:= Pos('http://', s);
            manager.container.pageLinks.Add(EncodeURL(GetString(s, '"', '"')));
            s:= StringReplace(s, '"', '', []);
            s:= StringReplace(s, '"', '', []);
            Delete(s, j, 10);
            j:= Pos('http://', s);
          until j = 0;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;
  
    // Mangacow link page
  function GetMangaCowLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
	s:= DecodeUrl(WebsiteRoots[MANGACOW_ID,1] + URL + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
	                 s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('id="sct_img_mng_enl"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;
  
    function GetSenMangaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[SENMANGA_ID,1] + URL + IntToStr(workCounter+1) + '/');
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos(' onerror=', parse.Strings[i])>0) then
        begin
          s:= EncodeURL(GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src=')));
          if Pos('http://', s) = 0 then
            s:= WebsiteRoots[SENMANGA_ID,1] + s;
          manager.container.pageLinks.Strings[workCounter]:= s;
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaTradersLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= WebsiteRoots[MANGATRADERS_ID,1] + URL + '/page/' + IntToStr(workCounter+1);
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('"image_display"', parse.Strings[i])>0) then
        begin
          s:= GetAttributeValue(GetTagAttribute(parse.Strings[i+4], 'src='));
          if s <> '' then
            manager.container.pageLinks.Strings[workCounter]:= s
          else
            manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i+12], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;

  function GetMangaEdenLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if manager.container.mangaSiteID = MANGAEDEN_ID then
      s:= WebsiteRoots[MANGAEDEN_ID,1] + URL + IntToStr(workCounter+1) + '/'
    else
      s:= WebsiteRoots[PERVEDEN_ID,1] + URL + IntToStr(workCounter+1) + '/';
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= parse.Count-1 downto 0 do
        if (Pos('"mainImg"', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;
  
    function GetKivmangaLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    s:= DecodeUrl(WebsiteRoots[KIVMANGA_ID,1] + URL + '/' + IntToStr(workCounter+1));
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
        if (Pos('class="picture"', parse.Strings[i])>0) then
        begin
          s:= WebsiteRoots[KIVMANGA_ID,1] + KIVMANGA_BROWSER + GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
          manager.container.pageLinks.Strings[workCounter]:= EncodeURL(s);
          break;
        end;
    end;
    parse.Free;
    l.Free;
  end;
  
    function GetMangacanLinkPage: Boolean;
  var
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    if Pos('http://', URL) = 0 then
      s:= WebsiteRoots[MANGACAN_ID,1] + '/' + URL
    else
      s:= URL;
    Result:= GetPage(TObject(l),
                     s,
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;
if parse.Count>0 then begin
  manager.container.pageLinks.Clear;  
  for i:= 0 to parse.Count-1 do
    if (Pos('<img alt=', parse.Strings[i])>0) then
    begin
	s:= GetAttributeValue(GetTagAttribute(parse.Strings[i], 'src='));
	s:= StringReplace(s, 'https://', 'http://', [rfReplaceAll]);
	s:= StringReplace(s, 'mangas/', WebsiteRoots[MANGACAN_ID,1] + '/mangas/', [rfReplaceAll]);
      manager.container.pageLinks.Add(EncodeURL(s));
    end;
end;
    parse.Free;
    l.Free;
  end;

  function GetGEHentaiLinkPage: Boolean;
  var
    s1,s2,
    s: String;
    j,
    i: Cardinal;
    l: TStringList;
  begin
    l:= TStringList.Create;
    Result:= GetPage(TObject(l),
                     URL,// + IntToStr(workCounter+1),
                     manager.container.manager.retryConnect);
    parse:= TStringList.Create;
    Parser:= TjsFastHTMLParser.Create(PChar(l.Text));
    Parser.OnFoundTag := OnTag;
    Parser.OnFoundText:= OnText;
    Parser.Exec;
    Parser.Free;

    if parse.Count>0 then
    begin
      for i:= 0 to parse.Count-1 do
      begin
        if Pos('http://ehgt.org/g/n.png', parse.Strings[i])>0 then
        begin
          s:= GetAttributeValue(GetTagAttribute(parse.Strings[i-1], 'href='));
          s1:= manager.anotherURL+' ';
          s2:= s+' ';
          Delete(s1, 1, 13);
          Delete(s2, 1, 13);
          // compare 2 strings to determine new URL
          if StrToInt(GetString(s1, '-', ' ')) < StrToInt(GetString(s2, '-', ' ')) then
          begin
            manager.anotherURL:= s;
          end;
        end;
        if (Pos('<div id="i3">', parse.Strings[i])>0) then
        begin
          manager.container.pageLinks.Strings[workCounter]:= GetAttributeValue(GetTagAttribute(parse.Strings[i+2], 'src='));
          manager.container.pageLinks.Strings[workCounter]:= StringReplace(manager.container.pageLinks.Strings[workCounter], '&amp;', '&', [rfReplaceAll]);
          // s:= manager.container.pageLinks.Strings[workCounter];
          break;
        end;
      end;
    end;
    parse.Free;
    l.Free;
  end;

var
  s: String;

begin
  if manager.container.pageLinks.Strings[workCounter] <> 'W' then exit;
  if manager.container.mangaSiteID = ANIMEA_ID then
    Result:= GetAnimeALinkPage
  else
  if manager.container.mangaSiteID = MANGATRADERS_ID then
    Result:= GetMangaTradersLinkPage
  else
  if manager.container.mangaSiteID = MANGAHERE_ID then
    Result:= GetMangaHereLinkPage
  else
  if manager.container.mangaSiteID = MANGAINN_ID then
    Result:= GetMangaInnLinkPage
  else
  if manager.container.mangaSiteID = OURMANGA_ID then
    Result:= GetOurMangaLinkPage
  else
  if manager.container.mangaSiteID = KISSMANGA_ID then
    Result:= GetKissMangaLinkPage
  else
  if manager.container.mangaSiteID = BATOTO_ID then
    Result:= GetBatotoLinkPage
  else
  if manager.container.mangaSiteID = MANGA24H_ID then
    Result:= GetManga24hLinkPage
  else
  if manager.container.mangaSiteID = VNSHARING_ID then
    Result:= GetVnSharingLinkPage
  else
  if manager.container.mangaSiteID = HENTAI2READ_ID then
    Result:= GetHentai2ReadLinkPage
  else
  if manager.container.mangaSiteID = FAKKU_ID then
    Result:= GetFakkuLinkPage
  else
  if manager.container.mangaSiteID = TRUYEN18_ID then
    Result:= GetTruyen18LinkPage
  else
  if manager.container.mangaSiteID = MANGAREADER_ID then
    Result:= GetMangaReaderLinkPage
  else
  if manager.container.mangaSiteID = MANGAPARK_ID then
    Result:= GetMangaParkLinkPage
  else
  if manager.container.mangaSiteID = MANGAFOX_ID then
    Result:= GetMangaFoxLinkPage
  else
  if manager.container.mangaSiteID = STARKANA_ID then
    Result:= GetStarkanaLinkPage
  else
  if manager.container.mangaSiteID = EATMANGA_ID then
    Result:= GetEatMangaLinkPage
  else
  if manager.container.mangaSiteID = MANGAPANDA_ID then
    Result:= GetMangaPandaLinkPage
  else
  if manager.container.mangaSiteID = MANGAGO_ID then
    Result:= GetMangaGoLinkPage
  else
  if manager.container.mangaSiteID = MANGASTREAM_ID then
    Result:= GetMangaStreamLinkPage
  else
  if manager.container.mangaSiteID = REDHAWKSCANS_ID then
    Result:= GetRedHawkScansLinkPage
  else
  if manager.container.mangaSiteID = S2SCAN_ID then
    Result:= GetS2scanLinkPage
  else
  if manager.container.mangaSiteID = EGSCANS_ID then
    Result:= GetEGScansLinkPage
  else
  if manager.container.mangaSiteID = ESMANGAHERE_ID then
    Result:= GetEsMangaHereLinkPage
  else
  if manager.container.mangaSiteID = SUBMANGA_ID then
    Result:= GetSubMangaLinkPage
  else
  if manager.container.mangaSiteID = ANIMEEXTREMIST_ID then
    Result:= GetAnimeExtremistLinkPage
  else
  if manager.container.mangaSiteID = KOMIKID_ID then
    Result:= GetKomikidLinkPage
  else
  if manager.container.mangaSiteID = PECINTAKOMIK_ID then
    Result:= GetPecintaKomikLinkPage
  else
  if manager.container.mangaSiteID = MABUNS_ID then
    Result:= GetMabunsLinkPage
  else
  if manager.container.mangaSiteID = MANGAESTA_ID then
    Result:= GetMangaEstaLinkPage
  else
  if manager.container.mangaSiteID = PURURIN_ID then
    Result:= GetPururinLinkPage
  else
  if manager.container.mangaSiteID = HUGEMANGA_ID then
    Result:= GetHugeMangaLinkPage
  else
  if manager.container.mangaSiteID = ANIMESTORY_ID then
    Result:= GetAnimeStoryLinkPage
  else
  if manager.container.mangaSiteID = SCANMANGA_ID then
    Result:= GetScanMangaLinkPage
  else
  if manager.container.mangaSiteID = TURKCRAFT_ID then
    Result:= GetTurkcraftLinkPage
  else
  if manager.container.mangaSiteID = MANGAVADISI_ID then
    Result:= GetMangaVadisiLinkPage
  else
  if manager.container.mangaSiteID = MANGAFRAME_ID then
    Result:= GetMangaFrameLinkPage
  else
  if manager.container.mangaSiteID = MANGAAR_ID then
    Result:= GetMangaArLinkPage
  else
  if manager.container.mangaSiteID = MANGAAE_ID then
    Result:= GetMangaAeLinkPage
  else
  if manager.container.mangaSiteID = CENTRALDEMANGAS_ID then
    Result:= GetCentralDeMangasLinkPage
  else
  if manager.container.mangaSiteID = MANGACOW_ID then
    Result:= GetMangaCowLinkPage
  else
  if manager.container.mangaSiteID = SENMANGA_ID then
    Result:= GetSenMangaLinkPage
  else
  if manager.container.mangaSiteID = TRUYENTRANHTUAN_ID then
    Result:= GetTruyenTranhTuanLinkPage
  else
  if manager.container.mangaSiteID = BLOGTRUYEN_ID then
    Result:= GetBlogTruyenLinkPage
  else
  if (manager.container.mangaSiteID = MANGAEDEN_ID) OR
     (manager.container.mangaSiteID = PERVEDEN_ID) then
    Result:= GetMangaEdenLinkPage
  else
  if manager.container.mangaSiteID = KIVMANGA_ID then
    Result:= GetKivmangaLinkPage
  else
  if manager.container.mangaSiteID = MANGACAN_ID then
    Result:= GetMangacanLinkPage
  else
  if manager.container.mangaSiteID = GEHENTAI_ID then
    Result:= GetGEHentaiLinkPage;
end;

procedure   TDownloadThread.SetChangeDirectoryFalse;
begin
  isChangeDirectory:= FALSE;
end;

procedure   TDownloadThread.SetChangeDirectoryTrue;
begin
  isChangeDirectory:= TRUE;
end;

function    TDownloadThread.DownloadPage: Boolean;
var
  fileSize: Cardinal;

  function  SavePage(URL: String; const Path, name: String; const Reconnect: Cardinal): Boolean;
  var
    header  : array [0..3] of Byte;
    ext     : String;
    HTTP    : THTTPSend;
    i       : Cardinal;
    counter : Cardinal = 0;
    s       : String;
    dest,
    source  : TPicture;
    fstream : TFileStreamUTF8;

  begin
    if (FileExists(Path+'/'+name+'.jpg')) OR
       (FileExists(Path+'/'+name+'.png')) OR
       (FileExists(Path+'/'+name+'.gif')) OR
       (Pos('http', URL) = 0) then
    begin
      Result:= TRUE;
      exit;
    end;
    Result:= FALSE;
    HTTP:= THTTPSend.Create;
    HTTP.ProxyHost:= Host;
    HTTP.ProxyPort:= Port;
    HTTP.ProxyUser:= User;
    HTTP.ProxyPass:= Pass;

    if manager.container.mangaSiteID <> MANGAAR_ID then
      HTTP.UserAgent:='curl/7.21.0 (i686-pc-linux-gnu) libcurl/7.21.0 OpenSSL/0.9.8o zlib/1.2.3.4 libidn/1.18';

    if manager.container.mangaSiteID = HENTAI2READ_ID then
      HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[HENTAI2READ_ID,1]+'/')
    else
    if manager.container.mangaSiteID = MANGAGO_ID then
      HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[MANGAGO_ID,1]+'/')
    else
    if manager.container.mangaSiteID = ANIMEEXTREMIST_ID then
    begin
      HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[ANIMEEXTREMIST_ID,1]+'/');
    end
    else
    if manager.container.mangaSiteID = KISSMANGA_ID then
      HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[KISSMANGA_ID,1]+'/')
    else
    if manager.container.mangaSiteID = CENTRALDEMANGAS_ID then
      HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[CENTRALDEMANGAS_ID,1]+'/')
    else
    if manager.container.mangaSiteID = VNSHARING_ID then
      HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[VNSHARING_ID,1]+'/')
    else
    if  manager.container.mangaSiteID = GEHENTAI_ID then
      HTTP.Headers.Insert(0, 'Referer:'+manager.container.pageLinks.Strings[workCounter]);
    while (NOT HTTP.HTTPMethod('GET', URL)) OR
          (HTTP.ResultCode >= 500) OR
          (HTTP.ResultCode = 403) do
    begin
      if Reconnect <> 0 then
      begin
        if Reconnect <= counter then
        begin
          HTTP.Free;
          exit;
        end;
        Inc(counter);
      end;
      HTTP.Clear;
      Sleep(500);
    end;

    while (HTTP.ResultCode = 302) OR (HTTP.ResultCode = 301) do
    begin
      URL:= CheckRedirect(HTTP);
      HTTP.Clear;
      HTTP.RangeStart:= 0;
      if Pos(HENTAI2READ_ROOT, URL) <> 0 then
        HTTP.Headers.Insert(0, 'Referer:'+HENTAI2READ_ROOT+'/')
      else
      if Pos('bp.blogspot.com', URL) <> 0 then
        HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[KISSMANGA_ID,1]+'/')
      else
      if Pos('mangas.centraldemangas.com', URL) <> 0 then
        HTTP.Headers.Insert(0, 'Referer:'+WebsiteRoots[CENTRALDEMANGAS_ID,1]+'/');
      while (NOT HTTP.HTTPMethod('GET', URL)) OR
            (HTTP.ResultCode >= 500) do
      begin
        if Reconnect <> 0 then
        begin
          if Reconnect <= counter then
          begin
            HTTP.Free;
            exit;
          end;
          Inc(counter);
        end;
        HTTP.Clear;
        Sleep(500);
      end;
    end;
    HTTP.Document.Seek(0, soBeginning);
    HTTP.Document.Read(header[0], 4);
    if (header[0] = JPG_HEADER[0]) AND
       (header[1] = JPG_HEADER[1]) AND
       (header[2] = JPG_HEADER[2]) then
      ext:= '.jpg'
    else
    if (header[0] = PNG_HEADER[0]) AND
       (header[1] = PNG_HEADER[1]) AND
       (header[2] = PNG_HEADER[2]) then
      ext:= '.png'
    else
    if (header[0] = GIF_HEADER[0]) AND
       (header[1] = GIF_HEADER[1]) AND
       (header[2] = GIF_HEADER[2]) then
      ext:= '.gif'
    else
      ext:= '';
    fstream:= TFileStreamUTF8.Create(Path+'/'+name+ext, fmCreate);
    HTTP.Document.SaveToStream(fstream);
    fstream.Free;
  //    HTTP.Document.SaveToFile(Path+'/'+name+ext);
    HTTP.Free;
    Result:= TRUE;
  end;

var
  lastTime, curTime  : Cardinal;
  s: String;
label
  start;

begin
start:
  if manager.container.mangaSiteID = GEHENTAI_ID then
  begin
    Sleep(500);
    lastTime:= fmdGetTickCount;

   // anotherURLBackup:= manager.anotherURL;
    GetLinkPageFromURL(anotherURL);
    curTime:= fmdGetTickCount-lastTime;
    if curTime<3000 then
      Sleep(3000-curTime)
    else
      Sleep(300);
  end;

  if (manager.container.pageLinks.Strings[workCounter] = '') OR
     (manager.container.pageLinks.Strings[workCounter] = 'W') then exit;
  SavePage(manager.container.pageLinks.Strings[workCounter],
           manager.container.downloadInfo.SaveTo+
           '/'+manager.container.chapterName.Strings[manager.container.currentDownloadChapterPtr],
           Format('%.3d', [workCounter+1]),
           manager.container.manager.retryConnect);

  SetCurrentDirUTF8(oldDir);
  if NOT Terminated then
    manager.container.pageLinks.Strings[workCounter]:= '';
end;

// ----- TTaskThread -----

constructor TTaskThread.Create;
begin
  anotherURL  := '';
  isTerminated:= FALSE;
  isSuspended := TRUE;
  FreeOnTerminate:= TRUE;
  threads     := TDownloadThreadList.Create;
  inherited Create(FALSE);
end;

destructor  TTaskThread.Destroy;
begin
  Stop;
  threads.Free;
  isTerminated:= TRUE;
  inherited Destroy;
end;

procedure   TTaskThread.CallMainFormRepaint;
begin
  if MainForm.isCanRefreshForm then
  begin
    MainForm.vtDownload.Repaint;
    MainForm.isCanRefreshForm:= FALSE;
  end;
end;

procedure   TTaskThread.CallMainFormCompressRepaint;
begin
  container.downloadInfo.Status:= Format('%s (%d/%d)', [stIsCompressing, container.currentDownloadChapterPtr, container.chapterLinks.Count]);
  MainForm.vtDownload.Repaint;
end;

procedure   TTaskThread.CallMainFormRepaintImm;
begin
  MainForm.vtDownload.Repaint;
  MainForm.isCanRefreshForm:= FALSE;
end;

procedure   TTaskThread.Compress;
var
  Compresser: TCompress;
begin
  if (container.manager.compress >= 1) then
  begin
    Sleep(100);
    Synchronize(CallMainformCompressRepaint);
    Compresser:= TCompress.Create;
    case container.manager.compress of
      1: Compresser.ext:= '.zip';
      2: Compresser.ext:= '.cbz';
      3: Compresser.ext:= '.pdf';
    end;
    Compresser.CompressionQuality:= OptionPDFQuality;
    Compresser.Path:= container.downloadInfo.SaveTo+'/'+
                      container.chapterName.Strings[container.currentDownloadChapterPtr];
    Compresser.Execute;
    Compresser.Free;
  end;
end;

procedure   TTaskThread.ShowBaloon;
begin
  MainForm.TrayIcon.BalloonHint:= '"'+container.downloadInfo.title+'" - '+stFinish;
  MainForm.TrayIcon.ShowBalloonHint;
end;

procedure   TTaskThread.Checkout;
var
  i, currentMaxThread: Cardinal;
  s: String;
begin
  // ugly code, need to be fixed later

  if (container.mangaSiteID = GEHENTAI_ID) AND (container.manager.maxDLThreadsPerTask>4) then
    currentMaxThread:= 4
  else
  if (container.mangaSiteID = EATMANGA_ID) then
    currentMaxThread:= 1
  else
    currentMaxThread:= container.manager.maxDLThreadsPerTask;

  if container.mangaSiteID = GEHENTAI_ID then
  begin
    if (container.workCounter <> 0) then
    begin
      repeat
        Sleep(32);
        s:= anotherURL;
        Delete(s, 1, 13);
        if (s <> '') AND
           (StrToInt(GetString(s+' ', '-', ' ')) = (container.workCounter+1)) then
          break;
      until FALSE;
    end;
    Sleep(500*currentMaxThread);
  end
  else
    Sleep(100);

  // main body of method
  // Each thread will be assigned job based on the counter
  if container.activeThreadCount > currentMaxThread then exit;
  for i:= 0 to currentMaxThread-1 do
  begin
    if i >= threads.Count then
    begin
      while isSuspended do Sleep(100);
      Inc(container.activeThreadCount);
      threads.Add(TDownloadThread.Create);
      if container.mangaSiteID = GEHENTAI_ID then
        threads.Items[threads.Count-1].anotherURL:= anotherURL;
      threads.Items[threads.Count-1].manager:= self;
      threads.Items[threads.Count-1].workCounter:= container.workCounter;
      threads.Items[threads.Count-1].checkStyle:= Flag;
      threads.Items[threads.Count-1].isSuspended:= FALSE;
      Inc(container.workCounter);
      if Flag = CS_GETPAGELINK then
        Inc(container.currentPageNumber);
      exit;
    end
    else
    if (threads.Items[i].isTerminated) then
    begin
      while isSuspended do Sleep(100);
      Inc(container.activeThreadCount);
      threads.Items[i]:= TDownloadThread.Create;
      if container.mangaSiteID = GEHENTAI_ID then
        threads.Items[i].anotherURL:= anotherURL;
      threads.Items[i].manager:= self;
      threads.Items[i].workCounter:= container.workCounter;
      threads.Items[i].checkStyle:= Flag;
      threads.Items[i].isSuspended:= FALSE;
      Inc(container.workCounter);
      if Flag = CS_GETPAGELINK then
        Inc(container.currentPageNumber);
      exit;
    end;
  end;
end;

procedure   TTaskThread.Execute;

  procedure  WaitFor;
  var
    done: Boolean;
    i   : Cardinal;
  begin
    repeat
      done:= TRUE;
      for i:= 0 to threads.Count-1 do
       // if threads[i].manager = @self then
          if NOT threads[i].isTerminated then
          begin
            done:= FALSE;
            sleep(100);
          end;
    until done;
  end;

var
  i, count: Cardinal;
begin
  while isSuspended do Sleep(100);

  while container.currentDownloadChapterPtr < container.chapterLinks.Count do
  begin
    if Terminated then exit;
    container.activeThreadCount:= 1;
    while isSuspended do Sleep(100);

    // get page number
    if container.currentPageNumber = 0 then
    begin
      if Terminated then exit;
      Stop(FALSE);
      threads.Add(TDownloadThread.Create);
      i:= threads.Count-1;
       // container.Status:= STATUS_PREPARE;
      threads.Items[threads.Count-1].manager:= self;
      threads.Items[threads.Count-1].workCounter:= container.workCounter;
      threads.Items[threads.Count-1].checkStyle:= CS_GETPAGENUMBER;
      threads.Items[threads.Count-1].isSuspended:= FALSE;
      CheckPath(container.downloadInfo.SaveTo+
                '/'+
                container.chapterName.Strings[container.currentDownloadChapterPtr]);
      while (isSuspended) OR (NOT threads.Items[threads.Count-1].isTerminated) do
        Sleep(100);
    end;

    //get page links
    if (container.mangaSiteID <> GEHENTAI_ID) then
    begin
      container.workCounter:= 0;
      container.downloadInfo.iProgress:= 0;
      while container.workCounter < container.pageLinks.Count do
      begin
        if Terminated then exit;
        Flag:= CS_GETPAGELINK;
        Checkout;
        container.downloadInfo.Progress:= Format('%d/%d', [container.workCounter, container.pageNumber]);
        container.downloadInfo.Status  :=
          Format('%s (%d/%d [%s])',
            [stPreparing,
             container.currentDownloadChapterPtr,
             container.chapterLinks.Count,
             container.chapterName.Strings[container.currentDownloadChapterPtr]]);
        Inc(container.downloadInfo.iProgress);
        {$IFDEF WIN32}
        MainForm.vtDownload.Repaint;
        {$ELSE}
        Synchronize(CallMainFormRepaint);
        {$ENDIF}
      end;
      WaitFor;
    end;

    //download pages
    container.workCounter:= 0;
    container.downloadInfo.iProgress:= 0;

    // If container doesn't have any image, we will skip the loop. Otherwise
    // download them
    if (container.pageLinks.Count > 0) then
    begin
      while container.workCounter < container.pageLinks.Count do
      begin
        if Terminated then exit;
        Flag:= CS_DOWNLOAD;
        Checkout;
        container.downloadInfo.Progress:= Format('%d/%d', [container.workCounter, container.pageLinks.Count]);
        container.downloadInfo.Status  :=
          Format('%s (%d/%d [%s])',
            [stDownloading,
             container.currentDownloadChapterPtr,
             container.chapterLinks.Count,
             container.chapterName.Strings[container.currentDownloadChapterPtr]]);
        Inc(container.downloadInfo.iProgress);
        {$IFDEF WIN32}
        MainForm.vtDownload.Repaint;
        {$ELSE}
        Synchronize(CallMainFormRepaint);
        {$ENDIF}
      end;
      WaitFor;
     // Synchronize(Compress);
      Compress;
    end;

    if Terminated then exit;
    container.currentPageNumber:= 0;
    container.pageLinks.Clear;
    Inc(container.currentDownloadChapterPtr);
  end;
  Synchronize(ShowBaloon);
  Terminate;
end;

procedure   TTaskThread.Stop(const check: Boolean = TRUE);
var
  i: Cardinal;
begin
  if check then
  begin
    if (container.workCounter >= container.pageLinks.Count) AND
       (container.currentDownloadChapterPtr >= container.chapterLinks.Count) then
    begin
      container.downloadInfo.Status  := stFinish;
      container.downloadInfo.Progress:= '';
      container.Status:= STATUS_FINISH;
      container.manager.CheckAndActiveTask(TRUE);
      {$IFDEF WIN32}
      MainForm.vtDownload.Repaint;
      {$ELSE}
      Synchronize(CallMainFormRepaintImm);
      {$ENDIF}
    end
    else
    begin
      container.downloadInfo.Status  := Format('%s (%d/%d)', [stStop, container.currentDownloadChapterPtr, container.chapterLinks.Count]);
      container.Status:= STATUS_STOP;
      container.manager.CheckAndActiveTask;
      {$IFDEF WIN32}
      MainForm.vtDownload.Repaint;
      {$ELSE}
      Synchronize(CallMainFormRepaintImm);
      {$ENDIF}
    end;
  end;
  threads.Clear;
end;

// ----- TTaskThreadContainer -----

constructor TTaskThreadContainer.Create;
begin
  chapterLinks     := TStringList.Create;
  chapterName      := TStringList.Create;
  pageLinks        := TStringList.Create;
  pageContainerLinks:= TStringList.Create;
  workCounter:= 0;
  currentPageNumber:= 0;
  currentDownloadChapterPtr:= 0;
  inherited Create;
end;

destructor  TTaskThreadContainer.Destroy;
begin
  // TODO: Need recheck
  repeat
    Sleep(64);
  until activeThreadCount = 0;
  thread.Terminate;
  pageContainerLinks.Free;
  pageLinks.Free;
  chapterName.Free;
  chapterLinks.Free;
  inherited Destroy;
end;

// ----- TDownloadManager -----

constructor TDownloadManager.Create;
begin
  inherited Create;

  // Create INI file
  ini:= TIniFile.Create(WORK_FOLDER + WORK_FILE);
  ini.CacheUpdates:= TRUE;

  downloadedChaptersList:= TStringList.Create;
  if FileExists(WORK_FOLDER + DOWNLOADEDCHAPTERS_FILE) then
    downloadedChaptersList.LoadFromFile(WORK_FOLDER + DOWNLOADEDCHAPTERS_FILE);

  containers:= TTaskThreadContainerList.Create;
  isFinishTaskAccessed:= FALSE;
  isRunningBackup     := FALSE;
  isRunningBackupDownloadedChaptersList:= FALSE;

  DownloadedChapterList := TList.Create;

  // Restore old INI file
  Restore;
end;

destructor  TDownloadManager.Destroy;
var i: Cardinal;
begin
  if containers.Count <> 0 then
    for i:= 0 to containers.Count-1 do
      if NOT containers.Items[i].thread.isTerminated then
        containers.Items[i].thread.Terminate;
  ini.Free;

  BackupDownloadedChaptersList;
  downloadedChaptersList.Free;

  DownloadedChapterList.Free;

  inherited Destroy;
end;

procedure   TDownloadManager.BackupDownloadedChaptersList;
begin
  if isRunningBackupDownloadedChaptersList then
    exit;
  isRunningBackupDownloadedChaptersList:= TRUE;
  downloadedChaptersList.SaveToFile(WORK_FOLDER + DOWNLOADEDCHAPTERS_FILE);
  isRunningBackupDownloadedChaptersList:= FALSE;
end;

procedure   TDownloadManager.Restore;
var
  s: String;
  tmp,
  i: Cardinal;
begin
  // Restore general information first
  if containers.Count > 0 then
  begin
    for i:= 0 to containers.Count-1 do
    begin
      containers.Items[i].Destroy;
    end;
    containers.Clear;
  end;
  tmp:= ini.ReadInteger('general', 'NumberOfTasks', 0);
  if tmp = 0 then exit;
  for i:= 0 to tmp-1 do
  begin
    containers.Add(TTaskThreadContainer.Create);
    containers.Items[i].manager:= self;
  end;

  // Restore chapter links, chapter name and page links
  for i:= 0 to containers.Count-1 do
  begin
    s:= ini.ReadString('task'+IntToStr(i), 'ChapterLinks', '');
    if s <> '' then
      GetParams(containers.Items[i].chapterLinks, s);
    s:= ini.ReadString('task'+IntToStr(i), 'ChapterName', '');
    if s <> '' then
      GetParams(containers.Items[i].chapterName, s);
    s:= ini.ReadString('task'+IntToStr(i), 'PageLinks', '');
    if s <> '' then
      GetParams(containers.Items[i].pageLinks, s);
    s:= ini.ReadString('task'+IntToStr(i), 'PageContainerLinks', '');
    if s <> '' then
      GetParams(containers.Items[i].pageContainerLinks, s);
    containers.Items[i].Status                   := ini.ReadInteger('task'+IntToStr(i), 'TaskStatus', 0);
    containers.Items[i].currentDownloadChapterPtr:= ini.ReadInteger('task'+IntToStr(i), 'ChapterPtr', 0);
    containers.Items[i].pageNumber               := ini.ReadInteger('task'+IntToStr(i), 'NumberOfPages', 0);
    containers.Items[i].currentPageNumber        := ini.ReadInteger('task'+IntToStr(i), 'CurrentPage', 0);

    containers.Items[i].downloadInfo.title   := ini.ReadString('task'+IntToStr(i), 'Title', 'NULL');
    containers.Items[i].downloadInfo.status  := ini.ReadString('task'+IntToStr(i), 'Status', 'NULL');
    containers.Items[i].downloadInfo.Progress:= ini.ReadString('task'+IntToStr(i), 'Progress', 'NULL');
    containers.Items[i].downloadInfo.website := ini.ReadString('task'+IntToStr(i), 'Website', 'NULL');
    containers.Items[i].downloadInfo.saveTo  := ini.ReadString('task'+IntToStr(i), 'SaveTo', 'NULL');
    containers.Items[i].downloadInfo.dateTime:= ini.ReadString('task'+IntToStr(i), 'DateTime', 'NULL');
    containers.Items[i].mangaSiteID:= GetMangaSiteID(containers.Items[i].downloadInfo.website);
  end;
  i:= 0;
  while i < containers.Count do
  begin
    if CompareStr(containers.Items[i].downloadInfo.dateTime, 'NULL') = 0 then
      containers.Delete(i)
    else
      Inc(i);
  end;
end;

procedure   TDownloadManager.Backup;
var
  i: Cardinal;
begin
  if isRunningBackup then exit;
  isRunningBackup:= TRUE;
  // Erase all sections
  for i:= 0 to ini.ReadInteger('general', 'NumberOfTasks', 0) do
    ini.EraseSection('task'+IntToStr(i));
  ini.EraseSection('general');

  // backup
  if containers.Count > 0 then
  begin
    ini.WriteInteger('general', 'NumberOfTasks', containers.Count);

    for i:= 0 to containers.Count-1 do
    begin
     // ini.WriteInteger('task'+IntToStr(i), 'NumberOfChapterLinks', containers.Items[i].chapterLinks.Count);
     // ini.WriteInteger('task'+IntToStr(i), 'NumberOfChapterName', containers.Items[i].chapterName.Count);
     // ini.WriteInteger('task'+IntToStr(i), 'NumberOfPageLinks', containers.Items[i].pageLinks.Count);

      ini.WriteString('task'+IntToStr(i), 'ChapterLinks', SetParams(containers.Items[i].chapterLinks));
      ini.WriteString('task'+IntToStr(i), 'ChapterName', SetParams(containers.Items[i].ChapterName));
      if containers.Items[i].pageLinks.Count > 0 then
        ini.WriteString('task'+IntToStr(i), 'PageLinks', SetParams(containers.Items[i].pageLinks));
      if containers.Items[i].pageContainerLinks.Count > 0 then
        ini.WriteString('task'+IntToStr(i), 'PageContainerLinks', SetParams(containers.Items[i].pageContainerLinks));

      ini.WriteInteger('task'+IntToStr(i), 'TaskStatus', containers.Items[i].Status);
      ini.WriteInteger('task'+IntToStr(i), 'ChapterPtr', containers.Items[i].currentDownloadChapterPtr);
      ini.WriteInteger('task'+IntToStr(i), 'NumberOfPages', containers.Items[i].pageNumber);
      ini.WriteInteger('task'+IntToStr(i), 'CurrentPage', containers.Items[i].currentPageNumber);

      ini.WriteString ('task'+IntToStr(i), 'Title', containers.Items[i].downloadInfo.title);
      ini.WriteString ('task'+IntToStr(i), 'Status', containers.Items[i].downloadInfo.status);
      ini.WriteString ('task'+IntToStr(i), 'Progress', containers.Items[i].downloadInfo.Progress);
      ini.WriteString ('task'+IntToStr(i), 'Website', containers.Items[i].downloadInfo.website);
      ini.WriteString ('task'+IntToStr(i), 'SaveTo', containers.Items[i].downloadInfo.saveTo);
      ini.WriteString ('task'+IntToStr(i), 'DateTime', containers.Items[i].downloadInfo.dateTime);
    end;
  end;
 // ini.UpdateFile;
  isRunningBackup:= FALSE;
end;

procedure   TDownloadManager.SaveJobList;
begin
  if isRunningBackup then while TRUE do Sleep(32);
  isRunningBackup:= TRUE;
  ini.UpdateFile;
  isRunningBackup:= FALSE;
end;

procedure   TDownloadManager.AddToDownloadedChaptersList(const ALink: String);
var
  i: Cardinal;
  LValue: String;
  Node  : PVirtualNode;
begin
  // generate LValue string
  LValue:= '';
  if MainUnit.MainForm.clbChapterList.RootNodeCount = 0 then exit;
  Node:= MainUnit.MainForm.clbChapterList.GetFirst;
  for i:= 0 to MainUnit.MainForm.clbChapterList.RootNodeCount-1 do
  begin
    if Node.CheckState = csCheckedNormal then
      LValue:= LValue+IntToStr(i) + SEPERATOR;
    Node:= MainUnit.MainForm.clbChapterList.GetNext(Node);
  end;
  if LValue = '' then exit;

  if DownloadedChaptersList.Count > 0 then
  begin
    i:= 0;
    while i < DownloadedChaptersList.Count do
    begin
      if CompareStr(ALink, DownloadedChaptersList.Strings[i]) = 0 then
      begin
        DownloadedChaptersList.Strings[i  ]:= ALink;
        DownloadedChaptersList.Strings[i+1]:=
          RemoveDuplicateNumbersInString(DownloadedChaptersList.Strings[i+1] + LValue);
        exit;
      end;
      Inc(i, 2);
    end;
  end;
  if DownloadedChaptersList.Count > 4000 then
  begin
    DownloadedChaptersList.Delete(0);
    DownloadedChaptersList.Delete(0);
  end;
  DownloadedChaptersList.Add(ALink);
  DownloadedChaptersList.Add(LValue);
end;

procedure   TDownloadManager.AddToDownloadedChaptersList(const ALink, AValue: String);
var
  i: Cardinal;
begin
  if DownloadedChaptersList.Count > 0 then
  begin
    i:= 0;
    while i < DownloadedChaptersList.Count do
    begin
      if CompareStr(ALink, DownloadedChaptersList.Strings[i]) = 0 then
      begin
        DownloadedChaptersList.Strings[i  ]:= ALink;
        DownloadedChaptersList.Strings[i+1]:=
          RemoveDuplicateNumbersInString(DownloadedChaptersList.Strings[i+1] + AValue);
        exit;
      end;
      Inc(i, 2);
    end;
  end;
  if DownloadedChaptersList.Count > 4000 then
  begin
    DownloadedChaptersList.Delete(0);
    DownloadedChaptersList.Delete(0);
  end;
  DownloadedChaptersList.Add(ALink);
  DownloadedChaptersList.Add(AValue);
end;

procedure   TDownloadManager.ReturnDownloadedChapters(const ALink: String);
var
  i: Cardinal;
begin
  // clear the list
  DownloadedChapterList.Clear;

  if DownloadedChaptersList.Count > 0 then
  begin
    i:= 0;
    while i < DownloadedChaptersList.Count do
    begin
      if CompareStr(ALink, DownloadedChaptersList.Strings[i]) = 0 then
      begin
        GetParams(DownloadedChapterList, DownloadedChaptersList.Strings[i+1]);
        exit;
      end;
      Inc(i, 2);
    end;
  end;
end;

procedure   TDownloadManager.AddTask;
begin
  containers.Add(TTaskThreadContainer.Create);
  containers.Items[containers.Count-1].manager:= self;
end;

procedure   TDownloadManager.CheckAndActiveTask(const isCheckForFMDDo: Boolean = FALSE);
var
  eatMangaCount: Cardinal = 0;
  batotoCount: Cardinal = 0;
  geCount    : Cardinal = 0;
  otherCount : Cardinal = 0;
  i          : Cardinal;
  count      : Cardinal = 0;
begin
  if containers.Count = 0 then exit;
  for i:= 0 to containers.Count-1 do
  begin
    if (containers.Items[i].Status = STATUS_DOWNLOAD) then
    begin
      if (containers.Items[i].mangaSiteID = GEHENTAI_ID) then
        Inc(geCount)
      else
      if (containers.Items[i].mangaSiteID = BATOTO_ID) then
        Inc(batotoCount)
      else
      if (containers.Items[i].mangaSiteID = EATMANGA_ID) then
        Inc(eatMangaCount);
      Inc(otherCount);
    end;
  end;

  if otherCount >= maxDLTasks then
    exit;

  for i:= 0 to containers.Count-1 do
  begin
    if containers.Items[i].Status = STATUS_DOWNLOAD then
    begin
      Inc(count);
    end
    else
    if containers.Items[i].Status = STATUS_WAIT then
    begin
      if containers.Items[i].mangaSiteID = GEHENTAI_ID then
      begin
        if geCount = 0 then
        begin
          ActiveTask(i);
          Inc(geCount);
          Inc(count);
        end;
      end
      else
      if containers.Items[i].mangaSiteID = EATMANGA_ID then
      begin
        if eatMangaCount = 0 then
        begin
          ActiveTask(i);
          Inc(eatMangaCount);
          Inc(count);
        end;
      end
      else
      begin
        ActiveTask(i);
        Inc(count);
      end;
    end;
    if count >= maxDLTasks then
      exit;
  end;

  if (count = 0) AND (isCheckForFMDDo) then
  begin
    case MainForm.cbOptionLetFMDDo.ItemIndex of
      DO_EXIT_FMD:
        begin
          MainForm.CloseNow;
          Sleep(2000);
          Halt;
        end;
      DO_TURNOFF:
        begin
          MainForm.CloseNow;
          Sleep(3000);
          fmdPowerOff;
          Halt;
        end;
      DO_HIBERNATE:
        begin
          Sleep(3000);
          fmdHibernate;
          Sleep(1000);
        end;
    end;
  end;
  MainForm.vtDownloadFilters;
end;

function    TDownloadManager.CanActiveTask(const pos: Cardinal): Boolean;
var
  eatMangaCount: Cardinal = 0;
  batotoCount: Cardinal = 0;
  geCount    : Cardinal = 0;
  i    : Cardinal;
  count: Cardinal = 0;
begin
  Result:= FALSE;

  if containers.Count = 0 then exit;
  if pos >= containers.Count then exit;

  for i:= 0 to containers.Count-1 do
  begin
    if (containers.Items[i].Status = STATUS_DOWNLOAD) AND (i<>pos) then
    begin
      if (containers.Items[i].mangaSiteID = GEHENTAI_ID) then
        Inc(geCount)
      else
      if (containers.Items[i].mangaSiteID = EATMANGA_ID) then
        Inc(eatMangaCount);
    end;
  end;

  if (containers.Items[pos].mangaSiteID = GEHENTAI_ID) AND (geCount > 0) then
    exit
  else
  if (containers.Items[pos].mangaSiteID = EATMANGA_ID) AND (eatMangaCount > 0) then
    exit;

  for i:= 0 to containers.Count-1 do
  begin
    if containers.Items[i].Status = STATUS_DOWNLOAD then
      Inc(count);
    if count >= maxDLTasks then
      exit;
  end;
  Result:= TRUE;
end;

procedure   TDownloadManager.CheckAndActiveTaskAtStartup;

  procedure   ActiveTaskAtStartup(const taskID: Cardinal);
  var
    i, pos: Cardinal;
  begin
    i:= maxDLTasks;
    if taskID >= containers.Count then exit;
    if (NOT Assigned(containers.Items[taskID])) then exit;
    if (containers.Items[taskID].Status = STATUS_WAIT) AND
       (containers.Items[taskID].Status = STATUS_STOP) AND
       (containers.Items[taskID].Status = STATUS_FINISH) then exit;
    containers.Items[taskID].Status:= STATUS_DOWNLOAD;
    containers.Items[taskID].thread:= TTaskThread.Create;
    containers.Items[taskID].thread.container:= containers.Items[taskID];
    containers.Items[taskID].thread.isSuspended:= FALSE;
  end;

var
  i    : Cardinal;
  count: Cardinal = 0;
begin
  if containers.Count = 0 then exit;
  for i:= 0 to containers.Count-1 do
  begin
    if containers.Items[i].Status = STATUS_DOWNLOAD then
    begin
      ActiveTaskAtStartup(i);
      Inc(count);
    end;
  end;
  MainForm.vtDownloadFilters;
end;

procedure   TDownloadManager.ActiveTask(const taskID: Cardinal);
var
  i, pos: Cardinal;
begin
  i:= maxDLTasks;
  // conditions
 // if pos >= maxDLTasks then exit;
  if taskID >= containers.Count then exit;
  if (NOT Assigned(containers.Items[taskID])) then exit;
  if (containers.Items[taskID].Status = STATUS_DOWNLOAD) AND
     (containers.Items[taskID].Status = STATUS_PREPARE) AND
     (containers.Items[taskID].Status = STATUS_FINISH) then exit;
  containers.Items[taskID].Status:= STATUS_DOWNLOAD;
  containers.Items[taskID].thread:= TTaskThread.Create;
  containers.Items[taskID].thread.container:= containers.Items[taskID];
  containers.Items[taskID].thread.isSuspended:= FALSE;
  // TODO
  MainForm.vtDownloadFilters;
end;

procedure   TDownloadManager.StopTask(const taskID: Cardinal; const isCheckForActive: Boolean = TRUE);
var
  i: Cardinal;
begin
  // conditions
  if taskID >= containers.Count then exit;
  if (containers.Items[taskID].Status <> STATUS_DOWNLOAD) AND
     (containers.Items[taskID].Status <> STATUS_WAIT) then exit;
  // check and stop any active thread
  if containers.Items[taskID].Status = STATUS_DOWNLOAD then
  begin
    for i:= 0 to containers.Items[taskID].thread.threads.Count-1 do
      if Assigned(containers.Items[taskID].thread.threads[i]) then
        containers.Items[taskID].thread.threads[i].Terminate;
    containers.Items[taskID].thread.Terminate;
    Sleep(250);
  end;
 // containers.Items[taskID].downloadInfo.Status:= Format('%s (%d/%d)', [stStop, containers.Items[taskID].currentDownloadChapterPtr, containers.Items[taskID].chapterLinks.Count]);
  containers.Items[taskID].downloadInfo.Status:= stStop;
  containers.Items[taskID].Status:= STATUS_STOP;

  if isCheckForActive then
  begin
    Backup;
    Sleep(1000);
    CheckAndActiveTask;
  end;
  MainForm.vtDownloadFilters;
end;

procedure   TDownloadManager.StopAllTasks;
var
  i, j: Cardinal;
begin
  if containers.Count = 0 then exit;
  // check and stop any active thread
  for i:= 0 to containers.Count-1 do
  begin
    if containers.Items[i].Status = STATUS_DOWNLOAD then
    begin
      for j:= 0 to containers.Items[i].thread.threads.Count-1 do
        if Assigned(containers.Items[i].thread.threads[j]) then
          containers.Items[i].thread.threads[j].Terminate;
      containers.Items[i].thread.Terminate;
      Sleep(250);
      containers.Items[i].Status:= STATUS_STOP;
    end
    else
    if containers.Items[i].Status = STATUS_WAIT then
    begin
      containers.Items[i].downloadInfo.Status:= stStop;
      containers.Items[i].Status:= STATUS_STOP;
    end;
  end;
  Backup;
  MainForm.vtDownload.Repaint;
  MainForm.vtDownloadFilters;
end;

procedure   TDownloadManager.StopAllDownloadTasksForExit;
var
  i, j: Cardinal;
begin
  if containers.Count = 0 then exit;
  for i:= 0 to containers.Count-1 do
  begin
    if containers.Items[i].Status = STATUS_DOWNLOAD then
    begin
      for j:= 0 to containers.Items[i].thread.threads.Count-1 do
        if Assigned(containers.Items[i].thread.threads[j]) then
          containers.Items[i].thread.threads[j].Terminate;
      containers.Items[i].thread.Terminate;
    end;
  end;
  Backup;
  MainForm.vtDownload.Repaint;
end;

procedure   TDownloadManager.FinishTask(const taskID: Cardinal);
begin
end;

// swap 2 task
function    TDownloadManager.Swap(const id1, id2: Cardinal): Boolean;
var
  tmp: TTaskThreadContainer;
begin
  if (id1 >= containers.Count) OR (id2 >= containers.Count) then exit(FALSE);
  tmp:= containers.Items[id1];
  containers.Items[id1]:= containers.Items[id2];
  containers.Items[id2]:= tmp;
  Result:= TRUE;
end;

// move a task down
function    TDownloadManager.MoveDown(const taskID: Cardinal): Boolean;
var
  tmp: TTaskThreadContainer;
begin
  if (taskID >= 0) AND (taskID < containers.Count-1) then
  begin
    tmp:= containers.Items[taskID];
    containers.Items[taskID]:= containers.Items[taskID+1];
    containers.Items[taskID+1]:= tmp;
    Result:= TRUE;
  end
  else
    Result:= FALSE;
  MainForm.vtDownloadFilters;
end;

// move a task up
function    TDownloadManager.MoveUp(const taskID: Cardinal): Boolean;
var
  tmp: TTaskThreadContainer;
begin
  if (taskID > 0) AND (taskID <= containers.Count-1) then
  begin
    tmp:= containers.Items[taskID];
    containers.Items[taskID]:= containers.Items[taskID-1];
    containers.Items[taskID-1]:= tmp;
    Result:= TRUE;
  end
  else
    Result:= FALSE;
  MainForm.vtDownloadFilters;
end;

procedure   TDownloadManager.RemoveTask(const taskID: Cardinal);
var
  i, j: Cardinal;
begin
  if taskID >= containers.Count then exit;
  // check and stop any active thread
  if containers.Items[taskID].Status = STATUS_DOWNLOAD then
  begin
    for i:= 0 to containers.Items[taskID].thread.threads.Count-1 do
      if Assigned(containers.Items[taskID].thread.threads[i]) then
        containers.Items[taskID].thread.threads[i].Terminate;
    containers.Items[taskID].thread.Terminate;
    Sleep(250);
    containers.Items[taskID].Status:= STATUS_STOP;
  end
  else
  if containers.Items[taskID].Status = STATUS_WAIT then
  begin
    containers.Items[taskID].downloadInfo.Status:= stStop;
    containers.Items[taskID].Status:= STATUS_STOP;
  end;
  containers.Delete(taskID);
end;

procedure   TDownloadManager.RemoveAllFinishedTasks;
var
  i, j: Cardinal;
begin
  if containers.Count = 0 then exit;
  // remove
  i:= 0;
  repeat
    if containers.Items[i].Status = STATUS_FINISH then
    begin
      containers.Delete(i);
    end
    else
      Inc(i);
  until i >= containers.Count;
end;

procedure   TDownloadManager.Sort(const AColumn: Cardinal);
  function  GetStr(const ARow: Cardinal): String;
  var
    tmp: Int64;
    dt : TDateTime;
  begin
    case AColumn of
      0: Result:= containers.Items[ARow].downloadInfo.title;
      3: Result:= containers.Items[ARow].downloadInfo.Website;
      4: Result:= containers.Items[ARow].downloadInfo.SaveTo;
      5: begin
           Result:= containers.Items[ARow].downloadInfo.dateTime;
           if TryStrToDateTime(Result, dt) then
             tmp:= DateTimeToUnix(dt)
           else
             tmp:= 0;
           Result:= IntToStr(tmp);
         end;
    end;
  end;

  procedure QSort(L, R: Cardinal);
  var i, j: Cardinal;
         X: String;
  begin
    X:= GetStr((L+R) div 2);
    i:= L;
    j:= R;
    while i<=j do
    begin
      case SortDirection of
        FALSE:
          begin
            case AColumn of
              5:
                begin
                  while StrToInt(GetStr(i)) < StrToInt(X) do Inc(i);
                  while StrToInt(GetStr(j)) > StrToInt(X) do Dec(j);
                end
              else
                begin
                  while StrComp(PChar(GetStr(i)), PChar(X))<0 do Inc(i);
                  while StrComp(PChar(GetStr(j)), PChar(X))>0 do Dec(j);
                end;
            end;
          end;
        TRUE:
          begin
            case AColumn of
              5:
                begin
                  while StrToInt(GetStr(i)) > StrToInt(X) do Inc(i);
                  while StrToInt(GetStr(j)) < StrToInt(X) do Dec(j);
                end
              else
                begin
                  while StrComp(PChar(GetStr(i)), PChar(X))>0 do Inc(i);
                  while StrComp(PChar(GetStr(j)), PChar(X))<0 do Dec(j);
                end;
            end;
          end;
      end;
      if i<=j then
      begin
        Swap(i, j);
        Inc(i);
        if j > 0 then
          Dec(j);
      end;
    end;
    if L < j then QSort(L, j);
    if i < R then QSort(i, R);
  end;

var
  i: Cardinal;

begin
  if containers.Count <= 2 then
    exit;
  sortColumn:= AColumn;
  QSort(0, containers.Count-1);
  MainForm.vtDownloadFilters;
end;

end.
