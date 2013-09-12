/*global jQuery, mediaWiki, console */

/**
 * Użycie: dodaj do [[Special:Mypage/common.js]] poniższe dwa wpisy:
 * 
 *   importScript('Wikipedysta:Matma Rex/bioindex-editor.js');
 *   importStylesheet('Wikipedysta:Matma Rex/bioindex-editor.css');
 * 
 * Wersja bardzo alfa.
 */

(function($, mw){
	if($('.bioindex-entry').length === 0) {
		// only load when relevant
		return;
	}
	
	mw.loader.load('jquery.spinner');
	mw.loader.load('mediawiki.api');
	mw.loader.load('jquery.wikibase.linkitem');
	
	function notify(text) {
		mw.notify(text, {autoHide: false, tag: 'bioindex'});
	}
	
	function errorHandler() {
		notify('Coś poszło nie tak. Odśwież stronę!');
		console.log(this);
		console.log(arguments);
	}
	
	function difflink(revid) {
		return "//www.wikidata.org/?oldid="+revid+"&diff=prev";
	}
	
	var wdLoginCheck = function(api) {
		return api.post({
			action: 'query',
			meta: 'userinfo'
		}).fail(errorHandler).done(function(resp) {
			var username = resp.query.userinfo.name;
			var anon = resp.query.userinfo.anon !== undefined;
			wdLoginCheck = $.noop; // self-destruct
			notify('Edytujesz Wikidane jako ' + username + (anon ? ' (niezalogowany!)' : '') + '.');
		});
	};
	
	$('#mw-content-text').on('click keypress', '.bioindex-entry .mw-editsection a', function(e) {
		var that = this;
		mw.loader.using(['jquery.spinner', 'mediawiki.api', 'jquery.wikibase.linkitem'], function() {
			/*global wikibase*/
			if(e.type === 'keypress' && e.which !== 13 && e.which !== 32) {
				return; // handle enter and space
			}
			e.preventDefault();
			
			var wdApi = new wikibase.RepoApi();
			wdLoginCheck(wdApi);
			
			var $entry = $(that).closest('.bioindex-entry');
			
			var $instructions = $('<div>').addClass('bioindex-help').append(
				$('<h3>').text('Instrukcja:'),
				$('<ul>').append(
					$('<li>').text('Zmiana wyświetlanego imienia i nazwiska spowoduje zmianę {{DEFAULTSORT: w artykule.'),
					$('<li>').text('Zmiana opisu spowoduje zmianę opisu artykułu na Wikidanych.'),
					$('<li>').text('Lata życia nie są na razie edytowalne z poziomu tego narzędzia. Aby je poprawić, zmodyfikuj kategorie urodzenia i śmierci w artykule.')
				)
			);
			
			var title = $entry.data('title');
			var defaultsort = $entry.data('defaultsort');
			var lifetime = $entry.data('lifetime');
			var description = $entry.data('description');
			var descriptionSuggestion = $entry.data('descriptionSuggestion');
			var itemid = $entry.data('itemid');
			
			// rebuild the entry with edit fields
			var $defaultsortEntry = $('<input>').val(defaultsort);
			var $articleLink = $('<a>').text('↗')
				.attr('href', mw.util.wikiGetlink(title))
				.attr('title', 'Przejdź do artykułu: '+title);
			var $descriptionEntry = $('<input>').val(description||descriptionSuggestion);
			var $saveButton = $('<button type=submit>').text('zapisz');
			var $cancelButton = $('<button type=reset>').text('anuluj');
			var $dummyForMeasurements = $('<span>').addClass('bioindex-dummy');
			
			var $form = $('<form>').append(
				$instructions,
				$defaultsortEntry,
				$articleLink,
				mw.html.escape(lifetime ? ' ('+lifetime+')' : ''),
				' – ',
				$descriptionEntry, ' ',
				$saveButton, ' ',
				$cancelButton,
				$dummyForMeasurements
			);
			$entry.empty().addClass('bioindex-entry-active').append( $form );
			$descriptionEntry.focus();
			
			// autosizing
			$dummyForMeasurements.css('font', $defaultsortEntry.css('font'));
			$defaultsortEntry.add($descriptionEntry).on('keyup keydown keypress change cut paste', function(){
				$dummyForMeasurements.text( 'X' + $(this).val() + 'X' );
				$(this).css('width', Math.min(Math.max($dummyForMeasurements.width(), 100), 600) );
			}).trigger('keyup');
			
			function rebuild() {
				$entry.empty().append(
					$articleLink.attr('title', title).text(defaultsort),
					mw.html.escape(lifetime ? ' ('+lifetime+')' : ''),
					' – ',
					description ? mw.html.escape(description) : $('<em>').text('brak opisu w Wikidanych'),
					' ',
					$('<span class=mw-editsection>[<a>edytuj</a>]</span>')
				);
				
				$entry.data('title', title);
				$entry.data('defaultsort', defaultsort);
				$entry.data('lifetime', lifetime);
				$entry.data('description', description);
				$entry.data('itemid', itemid);
			}
			
			function handleDefaultsort(){
				var promise = $.Deferred();
				
				var newtext = $.trim( $defaultsortEntry.val() );
				if(newtext == defaultsort) {
					promise.resolve(null);
					return promise;
				}
				
				notify('Edycja defaultsort jeszcze nie jest zaimplementowana :(');
				promise.reject(); // TODO
				return promise;
			}
			function handleDescription(){
				var promise = $.Deferred();
				
				var newtext = $.trim( $descriptionEntry.val() );
				if(newtext == description) {
					promise.resolve(null);
					return promise;
				}
				description = newtext;
				
				wdApi.post({
					action: 'tokens',
					type: 'edit'
				}).fail(errorHandler).done(function(resp){
					var wdtoken = resp.tokens.edittoken;
					var pagename = mw.config.get('wgPageName');
					console.log(wdtoken);
					
					wdApi.post({
						action: 'wbsetdescription',
						token: wdtoken,
						summary: "edit made via [[:pl:"+pagename+"|Polish Wikipedia index of biographies]]",
						site: 'plwiki',
						title: title,
						language: 'pl',
						value: description
					}).fail(errorHandler).done(function(resp){
						if(resp.success) {
							var diff = difflink(resp.entity.lastrevid);
							notify( $('<span>').append(
								'Zapisano zmiany we wpisie ' + mw.html.escape(title) + '. ',
								$('<a>').text('Diff').attr('href', diff),
								'.'
							) );
							promise.resolve(resp);
						} else {
							promise.reject(resp);
						}
					});
				});
				
				return promise;
			}
			
			$form.on('reset', function(e) {
				e.preventDefault();
				rebuild();
			});
			$form.on('submit', function(e) {
				e.preventDefault();
				var $spinner = $.createSpinner();
				$form.append(' ', $spinner);
				$.when(
					handleDefaultsort().fail(errorHandler),
					handleDescription().fail(errorHandler)
				).then(function(){
					$spinner.remove();
					rebuild();
				});
			});
		});
	});
})(jQuery, mediaWiki);
